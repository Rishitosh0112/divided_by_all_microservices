resource "aws_vpc_security_group_ingress_rule" "api_gateway_to_groups_service" {
  security_group_id            = data.aws_security_group.groups_service_tasks.id
  referenced_security_group_id = data.aws_security_group.api_gateway_tasks.id

  ip_protocol = "tcp"
  from_port   = 4002
  to_port     = 4002

  description = "Allow API Gateway Service Connect traffic to Groups Service"
}


resource "aws_vpc_security_group_egress_rule" "api_gateway_to_groups_service" {
  security_group_id            = data.aws_security_group.api_gateway_tasks.id
  referenced_security_group_id = data.aws_security_group.groups_service_tasks.id

  ip_protocol = "tcp"
  from_port   = 4002
  to_port     = 4002

  description = "Allow API Gateway Service Connect traffic to Groups Service"
}