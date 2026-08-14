# ------------------------------------------------------------------------------
# SUMMARY — Public API Gateway health-check route
#
# The Application Load Balancer (ALB) currently sends only /auth/*, /profiles/*,
# and /groups/* to the API Gateway target group. Its default route goes to the
# Frontend target group, which is intentionally empty until the Frontend Shell
# service is deployed. Therefore a public request to /health would otherwise
# receive ALB's HTTP 503 response even while API Gateway is healthy.
#
# This rule adds exactly one explicit route:
#
#   Browser or curl -> ALB listener port 80 -> /health -> API Gateway target group
#
# Priority 30 is deliberately unused: existing /mfe/* uses 10 and API paths use
# 20. No existing listener rule or default action is changed.
# ------------------------------------------------------------------------------

# Read the existing public HTTP listener rather than recreating it. The listener
# belongs to the already-created ALB and remains managed outside this Terraform
# directory.
data "aws_lb_listener" "app_http" {
  load_balancer_arn = data.aws_lb.app.arn
  port              = 80
}

# Send the exact /health path to the already healthy API Gateway ECS target
# group. The target group itself remains unchanged; this is only ALB routing.
resource "aws_lb_listener_rule" "api_gateway_health" {
  listener_arn = data.aws_lb_listener.app_http.arn
  priority     = 30

  action {
    type             = "forward"
    target_group_arn = data.aws_lb_target_group.api_gateway.arn
  }

  condition {
    path_pattern {
      values = ["/health"]
    }
  }

  tags = {
    Service = "api-gateway"
    Purpose = "public-health-check"
  }
}

# ------------------------------------------------------------------------------
# RUNTIME FLOW — What happens after Terraform applies this rule
#
# curl http://<ALB-DNS>/health
# -> ALB matches this priority-30 exact path rule
# -> ALB forwards to divided-by-all-api-gateway-tg
# -> the healthy API Gateway task returns Nginx's local HTTP 200 "ok" response
#
# All other routing remains unchanged: /mfe/* stays on priority 10, API business
# paths stay on priority 20, and unmatched paths still use the Frontend default.
# ------------------------------------------------------------------------------
