# ------------------------------------------------------------------------------
# SUMMARY — What this ECS task definition tells AWS to do
#
# Run the Nginx API Gateway Docker image from ECR as an ECS task on EC2.
#
# The container listens on port 80. Later, an ALB target group sends public
# /auth/*, /profiles/*, and /groups/* traffic to that port. Inside the VPC,
# Nginx calls the already-running private User and Groups Service Connect names.
#
# Give each task 256 CPU units, 512 MiB memory, a private awsvpc interface when
# the service starts it, and CloudWatch logging. This task has no application
# secrets: its job is HTTP routing, not database or credential handling.
# ------------------------------------------------------------------------------

# Read the existing ECR repository; Terraform does not build or push images.
data "aws_ecr_repository" "api_gateway" {
  name = "divided-by-all/api-gateway"
}

# Pin the exact image GitHub Actions pushed. Immutable tags make deployments and
# rollbacks traceable: this gateway task always runs the inspected image version.
variable "api_gateway_image_tag" {
  description = "Immutable ECR image tag for the Nginx API gateway."
  type        = string
  default     = "dd8a49014830bb902955d945df0ba43ded802dbf"
}

# Create the versioned ECS recipe. It records how Nginx should run but does not
# start a task until api_gateway_ecs_service.tf creates the ECS service.
resource "aws_ecs_task_definition" "api_gateway" {
  family                   = "divided-by-all-api-gateway"
  requires_compatibilities = ["EC2"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"

  # ECS uses this role to pull the private ECR image and send logs. The Nginx
  # process itself receives the intentionally empty application task role.
  execution_role_arn = data.aws_iam_role.ecs_task_execution.arn
  task_role_arn      = data.aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "api-gateway"
      image     = "${data.aws_ecr_repository.api_gateway.repository_url}:${var.api_gateway_image_tag}"
      essential = true

      # The name must remain stable because the later ECS service's ALB target
      # group attachment refers to this container and port by their names.
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
          protocol      = "tcp"
          name          = "api-gateway"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/divided-by-all/api-gateway"
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  tags = {
    Service = "api-gateway"
  }
}

# ------------------------------------------------------------------------------
# RUNTIME FLOW — What happens when ECS starts this task later
#
# ECS execution role pulls the Nginx image from ECR
# → Docker starts Nginx listening on port 80
# → ALB health checks /health and receives local HTTP 200
# → ALB forwards matching browser API requests to this task
# → Nginx resolves user-service:8000 and group-service:4002 through Service
#   Connect and proxies each request to the correct private backend
# → Nginx access/error logs appear in /ecs/divided-by-all/api-gateway
# ------------------------------------------------------------------------------
