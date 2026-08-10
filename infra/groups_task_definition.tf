# ------------------------------------------------------------------------------
# SUMMARY — What this ECS task definition tells AWS to do
#
# Run this Docker image:
# divided-by-all/groups-service:ec936eeb5d1eec6d4921955d9046c65819d47e66
#
# Give it:
# - 256 CPU units
# - 512 MiB memory
# - its own awsvpc network interface later, when an ECS service runs the task
#
# Expose:
# - port 4002
# - port name: groups-service
#
# Inject securely:
# - DATABASE_URL from AWS Secrets Manager
#
# Use IAM:
# - execution role: pull image, send logs, and fetch the secret before startup
# - task role: permissions available to the running application code
#
# Send logs to:
# - /ecs/divided-by-all/groups-service
# ------------------------------------------------------------------------------

# Look up the existing ECR repository where the Groups Docker image is stored.
# Terraform reads its repository URL; it does not create a repository.
data "aws_ecr_repository" "groups_service" {
  name = "divided-by-all/groups-service"
}

# Keep the deployed Docker image tag in one named variable.
# This is the latest verified image tag from GitHub Actions / ECR.
variable "groups_service_image_tag" {
  description = "Immutable ECR image tag for the Groups service."
  type        = string
  default     = "ec936eeb5d1eec6d4921955d9046c65819d47e66"
}

# Create a versioned ECS task definition.
# This defines HOW Groups runs; it does not start it.
resource "aws_ecs_task_definition" "groups_service" {
  # Human-readable task-definition family. AWS creates revisions, such as :1, :2.
  family = "divided-by-all-groups-service"

  # Give every ECS task its own network interface and security group.
  # This matches our IP-type ALB targets and service-level firewall design.
  network_mode = "awsvpc"

  # This task runs on our ECS-backed EC2 capacity, not on Fargate.
  requires_compatibilities = ["EC2"]

  # Reserved CPU units and memory for one Groups task.
  # 256 CPU units = one-quarter of a vCPU; memory is 512 MiB.
  cpu    = "256"
  memory = "512"

  # ECS uses this role before the container starts:
  # pull the ECR image, write CloudWatch logs, and fetch DATABASE_URL.
  execution_role_arn = data.aws_iam_role.ecs_task_execution.arn

  # Application code receives this role while it runs.
  # It currently has no application AWS permissions.
  task_role_arn = data.aws_iam_role.ecs_task.arn

  # Container definitions are AWS JSON, so jsonencode safely generates it from HCL.
  container_definitions = jsonencode([
    {
      # Container name used by ECS and later by Service Connect.
      name = "groups-service"

      # Run the exact immutable ECR image tag we verified.
      image = "${data.aws_ecr_repository.groups_service.repository_url}:${var.groups_service_image_tag}"

      # If this container stops, the whole ECS task is considered stopped.
      essential = true

      # The Node/Express Groups service listens on port 4002.
      # The port name is required later by ECS Service Connect.
      portMappings = [
        {
          name          = "groups-service"
          containerPort = 4002
          hostPort      = 4002
          protocol      = "tcp"
        }
      ]

      # ECS retrieves this secret at startup and injects it into the container
      # as process.env.DATABASE_URL. The value never appears in this file.
      secrets = [
        {
          name = "DATABASE_URL"
          # The secret contains JSON. This suffix tells ECS to inject only the
          # DATABASE_URL JSON key, not the entire JSON object.
          valueFrom = "${data.aws_secretsmanager_secret.groups_database_url.arn}:DATABASE_URL::"
        }
      ]

      # Send stdout/stderr from this container to the existing CloudWatch log group.
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/divided-by-all/groups-service"
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

# ------------------------------------------------------------------------------
# RUNTIME FLOW — What happens later when an ECS service starts this task
#
# ECS starts Groups task
# → execution role pulls the ECR image
# → execution role reads DATABASE_URL from Secrets Manager
# → ECS injects DATABASE_URL as an environment variable
# → Docker starts
# → Prisma migration runs
# → Node Groups service listens on port 4002
# → stdout and errors appear in CloudWatch Logs
# ------------------------------------------------------------------------------
