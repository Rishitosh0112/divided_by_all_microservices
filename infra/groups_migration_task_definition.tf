# Run exactly one Groups migration task for each release before the Groups ECS
# service is updated. This task is intentionally not an ECS service: it exits
# after Prisma has either applied pending migrations or verified that none exist.
#
# The deployment orchestrator must invoke this task with `aws ecs run-task`, wait
# for STOPPED, inspect the container exit code, and update the API service only
# after a zero exit code. Terraform defines the immutable task shape but never
# runs database migrations during `terraform apply`.
resource "aws_ecs_task_definition" "groups_migration" {
  family                   = "divided-by-all-groups-migration"
  network_mode             = "awsvpc"
  requires_compatibilities = ["EC2"]
  cpu                      = "256"
  memory                   = "512"

  execution_role_arn = data.aws_iam_role.ecs_task_execution.arn
  task_role_arn      = data.aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "groups-migration"
      image     = "${data.aws_ecr_repository.groups_service.repository_url}:${var.groups_service_image_tag}"
      essential = true
      command   = ["npm", "run", "db:migrate:deploy"]

      # Migrations must use the writer endpoint. The existing secret currently
      # contains that URL; read-replica URLs must never be supplied to this task.
      secrets = [
        {
          name      = "DATABASE_URL"
          valueFrom = "${data.aws_secretsmanager_secret.groups_database_url.arn}:DATABASE_URL::"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/divided-by-all/groups-service"
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "migration"
        }
      }
    }
  ])

  tags = {
    Service = "groups"
    Purpose = "database-migration"
  }
}

output "groups_migration_task_definition_arn" {
  description = "Task definition to invoke once before deploying a Groups release."
  value       = aws_ecs_task_definition.groups_migration.arn
}
