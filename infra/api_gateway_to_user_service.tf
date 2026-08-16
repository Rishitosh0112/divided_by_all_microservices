# ------------------------------------------------------------------------------
# API GATEWAY → USER SERVICE — private Service Connect network permission
#
# API Gateway's Nginx container sends /auth/* and /profiles/* requests to the
# user-service:8000 Service Connect alias. The client proxy connects over the
# VPC from the API Gateway task ENI, so its security group must explicitly be
# allowed to initiate TCP traffic to User Service port 8000.
# ------------------------------------------------------------------------------

resource "aws_vpc_security_group_egress_rule" "api_gateway_to_user_service" {
  security_group_id            = data.aws_security_group.api_gateway_tasks.id
  referenced_security_group_id = data.aws_security_group.user_service_tasks.id

  ip_protocol = "tcp"
  from_port   = 8000
  to_port     = 8000

  description = "Allow API Gateway Service Connect traffic to User Service"
}

# ------------------------------------------------------------------------------
# RUNTIME FLOW
#
# API Gateway task (sg-058a1cd52a83aa2b7)
#   → Service Connect user-service:8000
#   → User Service task (sg-0c795e8c7e4d028f5)
#
# Security groups are stateful: User Service response traffic is automatically
# permitted; no reciprocal egress rule is required for the response path.
# ------------------------------------------------------------------------------
