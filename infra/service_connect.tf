# Create a private DNS namespace for ECS Service Connect.
# "Private" means names in this namespace resolve only for resources inside
# our VPC; browsers on the internet cannot reach them.
resource "aws_service_discovery_private_dns_namespace" "app" {
  # The private DNS suffix for internal ECS services.
  # Later, Groups can be reachable as groups-service.divided-by-all.local.
  name = "divided-by-all.local"

  # Description shown in the AWS Cloud Map console.
  description = "Private DNS namespace for Divided By All ECS services"

  # Attach this namespace to the existing application VPC.
  # data.aws_vpc.app reads the VPC Terraform already knows about.
  vpc = data.aws_vpc.app.id
}
