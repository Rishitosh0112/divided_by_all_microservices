output "vpc_id" {
  value = data.aws_vpc.app.id
}

output "private_subnet_ids" {
  value = [
    data.aws_subnet.private_a.id,
    data.aws_subnet.private_b.id,
  ]
}

output "load_balancer_dns_name" {
  value = data.aws_lb.app.dns_name
}

output "ecs_cluster_arn" {
  value = data.aws_ecs_cluster.app.arn
}

output "api_gateway_target_group_arn" {
  value = data.aws_lb_target_group.api_gateway.arn
}
