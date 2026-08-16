resource "aws_vpc_security_group_ingress_rule" "frontend_shell_to_api_gateway" {
  security_group_id            = data.aws_security_group.api_gateway_tasks.id
  referenced_security_group_id = data.aws_security_group.frontend_shell_tasks.id

  ip_protocol = "tcp"
  from_port   = 80
  to_port     = 80

  description = "Allow Frontend Shell ECS tasks to call API Gateway through Service Connect"
}