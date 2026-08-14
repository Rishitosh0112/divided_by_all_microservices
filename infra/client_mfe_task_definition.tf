# ------------------------------------------------------------------------------
# SUMMARY — Client MFE ECS task blueprint
#
# Run the immutable Client Microfrontend (MFE) image from ECR on ECS EC2
# capacity. The image contains a small Nginx static-file server that listens on
# port 80 and translates the public ALB /mfe/* prefix to its built files.
#
# The Application Load Balancer is the only public entry point. This task gets a
# private awsvpc network interface and is registered later by its ECS service in
# the existing IP-type Client MFE target group.
# ------------------------------------------------------------------------------

# Read the existing ECR repository. Terraform deploys a pre-built immutable
# image; GitHub Actions remains responsible for building and pushing it.
data "aws_ecr_repository" "client_mfe" {
  name = "divided-by-all/client-mfe"
}

# Pin the exact successful GitHub Actions commit SHA so a later deployment or
# rollback always identifies one precise Client MFE image.
variable "client_mfe_image_tag" {
  description = "Immutable ECR image tag for the Client MFE static-site container."
  type        = string
  default     = "ce13a61c8796701a097b69ae7ebe6f263c3a8062"
}

# Create the versioned ECS recipe. A task is started only when the service in
# client_mfe_ecs_service.tf requests one.
resource "aws_ecs_task_definition" "client_mfe" {
  family                   = "divided-by-all-client-mfe"
  requires_compatibilities = ["EC2"]
  network_mode             = "awsvpc"
  # Static Nginx needs modest capacity. 256 MiB fits on the existing ECS EC2
  # hosts, each of which has 404 MiB still schedulable after the backend tasks.
  cpu    = "256"
  memory = "256"

  execution_role_arn = data.aws_iam_role.ecs_task_execution.arn
  task_role_arn      = data.aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "client-mfe"
      image     = "${data.aws_ecr_repository.client_mfe.repository_url}:${var.client_mfe_image_tag}"
      essential = true

      portMappings = [
        {
          name          = "client-mfe"
          containerPort = 80
          hostPort      = 80
          protocol      = "tcp"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/divided-by-all/client-mfe"
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  tags = {
    Service = "client-mfe"
  }
}

# ------------------------------------------------------------------------------
# RUNTIME FLOW — What ECS does with this task definition
#
# ECS execution role pulls the exact ECR image and starts Nginx on port 80
# -> task writes Nginx logs to /ecs/divided-by-all/client-mfe
# -> ALB health check / receives the static index response
# -> public /mfe/remoteEntry.js and chunk requests reach this task via its
#    later IP-type target-group registration
# ------------------------------------------------------------------------------
