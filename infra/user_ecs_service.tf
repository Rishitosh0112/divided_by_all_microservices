# ------------------------------------------------------------------------------
# SUMMARY — What this ECS service tells AWS to do
#
# Keep exactly one User task running from the User task definition.
#
# Give the task:
# - a private awsvpc network interface in the two application private subnets
# - the existing User task security group
# - EC2 capacity from the cluster's Auto Scaling capacity provider
#
# Register the private DNS alias user-service:8000 through ECS Service Connect.
# The Nginx API gateway already uses this exact name for /auth/* and /profiles/*
# requests. No ALB target group is attached because User is never directly
# public; only API gateway tasks may connect to it.
# ------------------------------------------------------------------------------

# Read the existing firewall attached to User ECS task network interfaces.
# Its inbound rule already permits port 8000 only from the API gateway task
# security group. Its default outbound rule permits the User task to make its
# private TLS connection to DocumentDB on port 27017.
data "aws_security_group" "user_service_tasks" {
  id = "sg-0c795e8c7e4d028f5"
}

# Create the ECS service that starts and replaces User Docker tasks.
resource "aws_ecs_service" "user_service" {
  name    = "divided-by-all-user-service"
  cluster = data.aws_ecs_cluster.app.arn

  # Always use the current task-definition revision Terraform created.
  task_definition = aws_ecs_task_definition.user_service.arn

  # Begin with one task. Service auto scaling is deliberately configured later,
  # after the service has proved it can start and connect to DocumentDB.
  desired_count = 1

  # This learning environment currently has no spare awsvpc ENI capacity for
  # an overlapping replacement. Stop the old User task before starting its
  # replacement when Service Connect logging changes, accepting brief downtime.
  availability_zone_rebalancing      = "DISABLED"
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  # Use the existing EC2 Auto Scaling capacity provider explicitly. If the
  # current EC2 host lacks room for this 512 MiB task, ECS capacity-provider
  # managed scaling requests another EC2 instance from its Auto Scaling Group.
  capacity_provider_strategy {
    capacity_provider = "Infra-ECS-Cluster-divided-by-all-cluster-e9cd13f5-AsgCapacityProvider-KyuME3ENzRYw"
    base              = 0
    weight            = 1
  }

  # Redeploy tasks if Terraform changes this service or its task definition.
  force_new_deployment = true

  # Terraform waits until ECS reaches a steady task count. If the Docker
  # container exits because of a secret, TLS, network, or database issue, apply
  # surfaces that problem instead of reporting a false deployment success.
  wait_for_steady_state = true

  network_configuration {
    # ECS chooses one of these private subnets and creates a task ENI there.
    subnets = [
      data.aws_subnet.private_a.id,
      data.aws_subnet.private_b.id,
    ]

    security_groups = [data.aws_security_group.user_service_tasks.id]

    # The User service is private; it has no public IPv4 address.
    assign_public_ip = false
  }

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_private_dns_namespace.app.arn

    # Emit proxy-side connection and reset information. The application has
    # separate ecs/* streams in this same group; this prefix identifies the
    # Service Connect sidecar streams during private-network troubleshooting.
    log_configuration {
      log_driver = "awslogs"

      options = {
        awslogs-group         = "/ecs/divided-by-all/user-service"
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "service-connect"
      }
    }

    # Record incoming requests at the User Service proxy. Keep query
    # parameters out of these diagnostic logs because they can contain data
    # that should not be written to CloudWatch.
    access_log_configuration {
      format                   = "TEXT"
      include_query_parameters = "DISABLED"
    }

    service {
      # Must match the named port in user_task_definition.tf.
      port_name = "user-service"

      # Service discovery's provider name inside divided-by-all.local.
      discovery_name = "user-service"

      client_alias {
        # Match api-gateway/nginx.conf exactly: user-service:8000.
        dns_name = "user-service"
        port     = 8000
      }
    }
  }

  tags = {
    Service = "user"
  }
}

# ------------------------------------------------------------------------------
# RUNTIME FLOW — What happens when this ECS service is applied
#
# ECS service requests one User task
# → the EC2 capacity provider places it, or asks the Auto Scaling Group for
#   another EC2 host when the existing host has no compatible capacity
# → ECS gives the task a private ENI and User task security group
# → execution role pulls the ECR image and reads the User runtime secret
# → Docker starts Node; Mongoose connects to DocumentDB with TLS
# → Service Connect registers user-service:8000 privately
# → API gateway can forward /auth/* and /profiles/* to that private alias
# → ECS maintains desired_count = 1 and starts a replacement if the task exits
# ------------------------------------------------------------------------------
