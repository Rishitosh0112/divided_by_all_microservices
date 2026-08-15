# ------------------------------------------------------------------------------
# SUMMARY — Frontend Shell ECS service behind the ALB default route
#
# Maintain one private Next.js Frontend Shell task and register its private IP in
# divided-by-all-frontend-tg. The ALB's default HTTP action already forwards all
# paths not matched by the MFE or API rules to this target group on port 3000.
#
# The task receives no public IP. Only the ALB security group can reach it.
# ------------------------------------------------------------------------------

data "aws_security_group" "frontend_shell_tasks" {
  filter {
    name   = "group-name"
    values = ["divided-by-all-frontend-tasks-sg"]
  }

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.app.id]
  }
}

resource "aws_ecs_service" "frontend_shell" {
  name            = "divided-by-all-frontend-shell"
  cluster         = data.aws_ecs_cluster.app.arn
  task_definition = aws_ecs_task_definition.frontend_shell.arn
  desired_count   = 1

  capacity_provider_strategy {
    capacity_provider = "Infra-ECS-Cluster-divided-by-all-cluster-e9cd13f5-AsgCapacityProvider-KyuME3ENzRYw"
    base              = 0
    weight            = 1
  }

  # One task is enough for this learning deployment. The ALB health check is
  # the readiness gate Terraform waits for before declaring deployment success.
  wait_for_steady_state             = true
  health_check_grace_period_seconds = 60

  network_configuration {
    subnets = [
      data.aws_subnet.private_a.id,
      data.aws_subnet.private_b.id,
    ]

    security_groups  = [data.aws_security_group.frontend_shell_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = data.aws_lb_target_group.frontend.arn
    container_name   = "frontend-shell"
    container_port   = 3000
  }

  tags = {
    Service = "frontend-shell"
  }
}

# ------------------------------------------------------------------------------
# RUNTIME FLOW — Public Frontend Shell request
#
# Browser -> ALB default route -> divided-by-all-frontend-tg -> Next.js port 3000
# -> Next.js page loads the deployed Client MFE from /mfe/remoteEntry.js
# -> shell API routes forward server-side requests through the ALB API paths
# ------------------------------------------------------------------------------
