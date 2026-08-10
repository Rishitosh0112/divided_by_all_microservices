data "aws_vpc" "app" {
  id = "vpc-00c3ef2ae0f63dac8"
}

data "aws_subnet" "private_a" {
  id = "subnet-07ac29b26c7808485"
}

data "aws_subnet" "private_b" {
  id = "subnet-0c10ba21e994b022e"
}

data "aws_lb" "app" {
  name = "divided-by-all-alb"
}

data "aws_ecs_cluster" "app" {
  cluster_name = "divided-by-all-cluster"
}

data "aws_iam_role" "ecs_task_execution" {
  name = "divided-by-all-ecs-task-execution-role"
}

data "aws_iam_role" "ecs_task" {
  name = "divided-by-all-ecs-task-role"
}

data "aws_lb_target_group" "frontend" {
  name = "divided-by-all-frontend-tg"
}

data "aws_lb_target_group" "client_mfe" {
  name = "divided-by-all-client-mfe-tg"
}

data "aws_lb_target_group" "api_gateway" {
  name = "divided-by-all-api-gateway-tg"
}