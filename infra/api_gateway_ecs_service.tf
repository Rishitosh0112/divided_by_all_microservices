# ------------------------------------------------------------------------------
# SUMMARY — What this ECS service tells AWS to do
#
# Keep one Nginx API Gateway task running from the API Gateway task definition.
#
# Connect it to two networks at once:
# - Public-entry side: the existing ALB target group sends API requests to Nginx
#   on container port 80 after the ALB listener matches /auth/*, /profiles/*,
#   or /groups/*.
# - Private-backend side: ECS Service Connect lets Nginx resolve user-service
#   and group-service by their stable private aliases.
#
# The task itself has no public IP. The ALB is the only public entry point.
# ------------------------------------------------------------------------------

# Read the existing API-gateway task firewall. Its inbound rule allows port 80
# only from the ALB security group, rather than from the public Internet.
data "aws_security_group" "api_gateway_tasks" {
  id = "sg-058a1cd52a83aa2b7"
}

# Create the service that maintains the Nginx container and registers each task
# IP with the existing IP-type ALB target group.
resource "aws_ecs_service" "api_gateway" {
  name            = "divided-by-all-api-gateway"
  cluster         = data.aws_ecs_cluster.app.arn
  task_definition = aws_ecs_task_definition.api_gateway.arn
  desired_count   = 1

  # Use ECS EC2 capacity and let the capacity provider request an additional
  # EC2 instance if no registered host has room for this 512 MiB task.
  capacity_provider_strategy {
    capacity_provider = "Infra-ECS-Cluster-divided-by-all-cluster-e9cd13f5-AsgCapacityProvider-KyuME3ENzRYw"
    base              = 0
    weight            = 1
  }

  # Ensure updates start a fresh task, and wait until the ALB/ECS deployment
  # reaches a steady state rather than hiding a failed Nginx or health check.
  force_new_deployment  = true
  wait_for_steady_state = true

  # Give Nginx time to start before ECS considers ALB health-check failures.
  health_check_grace_period_seconds = 30

  network_configuration {
    subnets = [
      data.aws_subnet.private_a.id,
      data.aws_subnet.private_b.id,
    ]

    security_groups  = [data.aws_security_group.api_gateway_tasks.id]
    assign_public_ip = false
  }

  # Attach Nginx to the existing ALB target group. The target group uses IP
  # targets because awsvpc tasks have their own ENI/private IP, not an EC2 host
  # port. The names must match the container and port mapping in the task def.
  load_balancer {
    target_group_arn = data.aws_lb_target_group.api_gateway.arn
    container_name   = "api-gateway"
    container_port   = 80
  }

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_private_dns_namespace.app.arn

    # There is intentionally no `service` block here. API Gateway does not need
    # to publish a Service Connect alias because the ALB reaches it through its
    # target group. Enabling Service Connect still makes this task a client able
    # to resolve the User and Groups aliases in the private namespace.
  }

  tags = {
    Service = "api-gateway"
  }
}

# ------------------------------------------------------------------------------
# RUNTIME FLOW — What happens when this service is applied
#
# ECS requests one Nginx task from the EC2 capacity provider
# → capacity provider finds a host or asks the Auto Scaling Group for one
# → ECS gives the task a private ENI and API-gateway security group
# → execution role pulls the image; Docker starts Nginx on port 80
# → ECS registers the task private IP in divided-by-all-api-gateway-tg
# → ALB calls /health; Nginx returns HTTP 200 locally
# → ALB marks the target healthy and forwards matching public API paths
# → Nginx resolves User/Groups via Service Connect and proxies privately
# ------------------------------------------------------------------------------
