# ------------------------------------------------------------------------------
# SUMMARY — What this ECS service tells AWS to do
#
# Keep exactly one Groups task running from the Groups task definition.
#
# Give the task:
# - its own awsvpc network interface in the two private subnets
# - the Groups task security group
# - ECS EC2 capacity from the cluster's default capacity-provider strategy
#
# Register it privately through ECS Service Connect:
# - service discovery name: groups-service
# - API gateway client alias: group-service:4002
#
# No ALB target group is attached.
# Groups is a private backend service; only the API gateway will call it later.
# ------------------------------------------------------------------------------

# Read the existing security group assigned to Groups ECS task network interfaces.
# Its rules control which other services may connect to Groups on port 4002.
data "aws_security_group" "groups_service_tasks" {
  id = "sg-053708700d6e0d132"
}

# Read the existing security group attached to the Groups PostgreSQL database.
# We use a security-group reference rather than an IP address: RDS can change
# its private IP during maintenance or replacement, while this permission
# continues to identify the database firewall correctly.
data "aws_security_group" "groups_postgres" {
  id = "sg-021d8689433f83353"
}

# Allow a Groups ECS task to open an outbound PostgreSQL connection to RDS.
# Security groups are stateful, so this single egress rule plus the existing
# RDS inbound rule is enough for the complete database conversation and its
# response traffic. It does NOT expose RDS to the Internet or to other tasks.
resource "aws_vpc_security_group_egress_rule" "groups_to_postgres" {
  security_group_id            = data.aws_security_group.groups_service_tasks.id
  referenced_security_group_id = data.aws_security_group.groups_postgres.id

  ip_protocol = "tcp"
  from_port   = 5432
  to_port     = 5432

  description = "Allow Groups ECS tasks to connect privately to Groups PostgreSQL"
}

# Create the ECS service that starts and keeps Groups tasks running.
resource "aws_ecs_service" "groups_service" {
  # Name shown in the ECS console.
  name = "divided-by-all-groups-service"

  # Run this service in the existing ECS cluster.
  cluster = data.aws_ecs_cluster.app.arn

  # Use the task-definition revision Terraform created.
  task_definition = aws_ecs_task_definition.groups_service.arn

  # Keep one Groups task running for this initial learning deployment.
  desired_count = 1

  # Explicitly use the EC2 Auto Scaling capacity provider already attached
  # to this ECS cluster. This prevents Terraform from trying to remove the
  # capacity strategy during later service updates.
  capacity_provider_strategy {
    capacity_provider = "Infra-ECS-Cluster-divided-by-all-cluster-e9cd13f5-AsgCapacityProvider-KyuME3ENzRYw"

    # base = 0 means no minimum task count is reserved on this provider.
    base = 0

    # weight = 1 sends all task placement to this provider.
    weight = 1
  }

  # Require ECS to start a fresh deployment whenever Terraform updates this
  # service configuration or points the service at a new task-definition revision.
  # This lets ECS replace the failed task with one using the corrected secret injection.
  force_new_deployment = true

  # Wait during Terraform apply until ECS reaches a steady state.
  # This helps us discover startup, secret, database, or capacity errors immediately.
  wait_for_steady_state = true

  # No load_balancer block is specified intentionally.
  # Groups is internal-only, so the ALB must not send browser traffic directly to it.

  network_configuration {
    # Give the task a private IP address in either of these private subnets.
    subnets = [
      data.aws_subnet.private_a.id,
      data.aws_subnet.private_b.id,
    ]

    # Attach the firewall dedicated to Groups ECS tasks.
    security_groups = [data.aws_security_group.groups_service_tasks.id]

    # The task gets no public IP address.
    # It communicates privately with RDS and later with API gateway.
    assign_public_ip = false
  }

  service_connect_configuration {
    # Turn on ECS Service Connect for this private service.
    enabled = true

    # Register the service in the private Cloud Map namespace we created.
    namespace = aws_service_discovery_private_dns_namespace.app.arn

    service {
      # Must match the named port in groups_task_definition.tf.
      port_name = "groups-service"

      # Service Connect registers this service internally as groups-service.
      discovery_name = "groups-service"

      client_alias {
        # The current Nginx API-gateway configuration calls group-service:4002.
        # This alias deliberately matches that existing configuration.
        dns_name = "group-service"

        # Requests to group-service use the Groups application port.
        port = 4002
      }
    }
  }

  tags = {
    Service = "groups"
  }
}

# ------------------------------------------------------------------------------
# RUNTIME FLOW — What happens when this ECS service is applied
#
# ECS service asks the cluster for capacity
# → cluster's EC2 Auto Scaling Group capacity provider places one Groups task
# → ECS gives the task a private network interface and Groups security group
# → execution role pulls the ECR image and reads DATABASE_URL
# → Docker runs Prisma migration, then starts Node on port 4002
# → ECS Service Connect registers group-service:4002 privately
# → Groups logs appear in /ecs/divided-by-all/groups-service
# → ECS keeps desired_count = 1; if the task stops, ECS starts a replacement
# ------------------------------------------------------------------------------
