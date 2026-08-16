# ------------------------------------------------------------------------------
# SUMMARY — Frontend Shell ECS task blueprint
#
# Run the immutable Next.js Frontend Shell image on ECS EC2 capacity. It listens
# on port 3000 and is the ALB's default public route. At build time, GitHub
# Actions embedded the public Client MFE remoteEntry.js URL in this image.
#
# At runtime, the Next.js server uses API_GATEWAY_URL to call the existing ALB
# API routes (/auth, /profiles, and /groups). Browser requests stay same-origin:
# they call the shell's /api routes, and the shell forwards them server-side.
# ------------------------------------------------------------------------------

data "aws_ecr_repository" "frontend_shell" {
  name = "divided-by-all/frontend-shell"
}


variable "frontend_shell_image_tag" {
  description = "Immutable ECR image tag for the Frontend Shell container."
  type        = string
  default     = "763d6c02e1a17a0cffa77207b154d6f11847e312"
}



resource "aws_ecs_task_definition" "frontend_shell" {
  family                   = "divided-by-all-frontend-shell"
  requires_compatibilities = ["EC2"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "256"

  execution_role_arn = data.aws_iam_role.ecs_task_execution.arn
  task_role_arn      = data.aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "frontend-shell"
      image     = "${data.aws_ecr_repository.frontend_shell.repository_url}:${var.frontend_shell_image_tag}"
      essential = true

      portMappings = [
        {
          name          = "frontend-shell"
          containerPort = 3000
          hostPort      = 3000
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "API_GATEWAY_URL"
          value = "http://api-gateway:80"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/divided-by-all/frontend-shell"
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  tags = {
    Service = "frontend-shell"
  }
}

# ------------------------------------------------------------------------------
# RUNTIME FLOW — Frontend Shell task
#
# ECS pulls the pinned image and starts Next.js on port 3000
# -> ALB health check / receives the rendered application response
# -> browser receives the Frontend Shell and loads /mfe/remoteEntry.js
# -> shell /api routes use API_GATEWAY_URL to call the ALB's existing API paths
# ------------------------------------------------------------------------------
