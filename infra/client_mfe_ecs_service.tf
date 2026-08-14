# ------------------------------------------------------------------------------
# SUMMARY — Keep one private Client MFE task behind the public ALB route
#
# This service maintains one Client MFE task on ECS EC2 capacity, gives it a
# private network interface in the two application subnets, and registers that
# task IP in the existing divided-by-all-client-mfe-tg target group.
#
# The ALB listener already owns the public mapping: /mfe/* -> this target group.
# The task has no public IP, and its security group accepts port 80 only from
# the ALB security group.
# ------------------------------------------------------------------------------

# Locate the existing Client MFE firewall by stable name in the application VPC.
# This data source does not create or loosen any security-group rules.
data "aws_security_group" "client_mfe_tasks" {
  filter {
    name   = "group-name"
    values = ["divided-by-all-client-mfe-tasks-sg"]
  }

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.app.id]
  }
}

resource "aws_ecs_service" "client_mfe" {
  name            = "divided-by-all-client-mfe"
  cluster         = data.aws_ecs_cluster.app.arn
  task_definition = aws_ecs_task_definition.client_mfe.arn
  desired_count   = 1

  # With one desired task, Availability Zone Rebalancing cannot improve
  # availability. Disabling it permits the deliberate stop-then-start rollout
  # below, which is required because the small EC2 hosts have no spare awsvpc
  # ENI slot for a temporary second Client MFE task.
  availability_zone_rebalancing = "DISABLED"

  capacity_provider_strategy {
    capacity_provider = "Infra-ECS-Cluster-divided-by-all-cluster-e9cd13f5-AsgCapacityProvider-KyuME3ENzRYw"
    base              = 0
    weight            = 1
  }

  # There is one Client MFE task and the small EC2 hosts have no spare awsvpc
  # ENI slot for a second temporary task. Permit ECS to stop the old task before
  # starting its replacement. This can cause a short /mfe/* interruption during
  # a Client MFE deployment, but avoids keeping a fifth EC2 instance solely for
  # zero-downtime rollout capacity.
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  # Terraform waits for the ALB health check to confirm the new static-site
  # task is usable, rather than reporting success immediately after submission.
  wait_for_steady_state             = true
  health_check_grace_period_seconds = 30

  network_configuration {
    subnets = [
      data.aws_subnet.private_a.id,
      data.aws_subnet.private_b.id,
    ]

    security_groups  = [data.aws_security_group.client_mfe_tasks.id]
    assign_public_ip = false
  }

  # Target group type is IP because awsvpc tasks have their own private ENI.
  load_balancer {
    target_group_arn = data.aws_lb_target_group.client_mfe.arn
    container_name   = "client-mfe"
    container_port   = 80
  }

  tags = {
    Service = "client-mfe"
  }
}

# ------------------------------------------------------------------------------
# RUNTIME FLOW — Client MFE service deployment
#
# ECS capacity provider finds available EC2 capacity (or asks the ASG for it)
# -> ECS creates a private task ENI with the Client MFE security group
# -> execution role pulls the pinned ECR image and starts Nginx on port 80
# -> ECS registers the task IP in divided-by-all-client-mfe-tg
# -> ALB health check / becomes healthy
# -> ALB path /mfe/* forwards remoteEntry.js and chunk requests to this task
# ------------------------------------------------------------------------------
