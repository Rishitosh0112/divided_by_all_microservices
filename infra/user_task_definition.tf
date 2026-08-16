# ------------------------------------------------------------------------------
# SUMMARY — What this ECS task definition tells AWS to do
#
# Run the TLS-ready User Docker image from ECR as an ECS task on EC2 capacity.
#
# Give each User task:
# - 256 CPU units (0.25 vCPU) and 512 MiB memory
# - its own awsvpc network interface when an ECS service starts it
# - private environment values from the User runtime secret
# - CloudWatch logging in /ecs/divided-by-all/user-service
#
# Expose named TCP port 8000 so ECS Service Connect can register the stable
# internal name user-service:8000. The public ALB will never target this task
# directly; only the API gateway will call it later.
# ------------------------------------------------------------------------------

# Read the existing ECR repository. Terraform does not create an image or a
# repository here; it simply constructs the image URI from the repository URL.
data "aws_ecr_repository" "user_service" {
  name = "divided-by-all/user-service"
}

# Keep the immutable image tag in one obvious place. This tag was built after
# the DocumentDB CA bundle was added to User/Dockerfile and pushed by GitHub
# Actions. Change this value only when deliberately deploying a newer image.
variable "user_service_image_tag" {
  description = "Immutable ECR image tag for the User service."
  type        = string
  default     = "7aab85dae4bb90c7c129a851924c3d45aa7c4782"
}

# Create a versioned task-definition blueprint. Applying this resource records
# a new revision in ECS; it does not yet start a Docker container.
resource "aws_ecs_task_definition" "user_service" {
  family = "divided-by-all-user-service"

  # ECS places this task on the existing EC2 Auto Scaling capacity provider.
  requires_compatibilities = ["EC2"]

  # awsvpc gives every task its own elastic network interface, private IP, and
  # task-level security group. This is why service-to-service firewall rules
  # can refer to a service security group rather than an EC2 host IP.
  network_mode = "awsvpc"

  cpu    = "256"
  memory = "512"

  # Execution role: ECS pulls ECR images, writes logs, and reads injected
  # secrets before Node starts. Task role: permissions available to Node code;
  # it remains deliberately empty for the current User application.
  execution_role_arn = data.aws_iam_role.ecs_task_execution.arn
  task_role_arn      = data.aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "user-service"
      image     = "${data.aws_ecr_repository.user_service.repository_url}:${var.user_service_image_tag}"
      essential = true

      portMappings = [
        {
          containerPort = 8000
          hostPort      = 8000
          protocol      = "tcp"
          name          = "user-service"
        }
      ]

      # Service Connect can use this essential-container health signal before
      # routing requests. Node 20 includes fetch, so this needs no extra image
      # package and keeps the probe inside the task's own network namespace.
      healthCheck = {
        command = [
          "CMD-SHELL",
          "node -e \"fetch('http://127.0.0.1:8000/health').then(r => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1))\"",
        ]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }

      # Non-sensitive runtime settings may be declared directly. The User
      # application reads PORT and NODE_ENV through process.env.
      environment = [
        { name = "PORT", value = "8000" },
        { name = "NODE_ENV", value = "production" },
      ]

      # The runtime secret is JSON. The :KEY:: suffix tells ECS to inject one
      # JSON key as one environment variable. Omitting the suffix would inject
      # the entire JSON object and make Mongoose/JWT receive invalid values.
      secrets = [
        {
          name      = "MONGO_URL"
          valueFrom = "${data.aws_secretsmanager_secret.user_runtime.arn}:MONGO_URL::"
        },
        {
          name      = "JWT_SECRET"
          valueFrom = "${data.aws_secretsmanager_secret.user_runtime.arn}:JWT_SECRET::"
        },
        {
          name      = "JWT_EXPIRES_IN"
          valueFrom = "${data.aws_secretsmanager_secret.user_runtime.arn}:JWT_EXPIRES_IN::"
        },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/divided-by-all/user-service"
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  tags = {
    Service = "user"
  }
}

# ------------------------------------------------------------------------------
# RUNTIME FLOW — What happens when ECS starts a User task from this definition
#
# ECS execution role pulls User image 7aab85d... from ECR
# → ECS execution role reads the three named JSON keys from Secrets Manager
# → ECS injects MONGO_URL, JWT_SECRET, and JWT_EXPIRES_IN into the container
# → Docker starts Node on port 8000 with the bundled DocumentDB CA certificate
# → Mongoose connects privately to DocumentDB using TLS
# → User service logs startup and health information to CloudWatch
# → Service Connect later makes the task reachable as user-service:8000
# ------------------------------------------------------------------------------
