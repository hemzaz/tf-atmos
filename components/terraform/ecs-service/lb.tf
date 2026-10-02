# Optional ALB attachment: the service's own target group and a listener rule
# on an existing listener (an alb instance's .https_listener_arn). Cloud Posse's
# aws-ecs-service reads the ALB through remote state and its alb_ingress
# module; here the listener ARN is an input (one rule, one target group; more
# target groups are part 2). Targets are task ENIs (awsvpc), so the target type
# is ip for Fargate and EC2 alike.

resource "aws_lb_target_group" "this" {
  #checkov:skip=CKV_AWS_378:TLS terminates at the ALB's HTTPS listener; targets are reached over plain HTTP inside the VPC by default (load_balancer.protocol)
  count = local.lb_enabled ? 1 : 0

  name                 = local.prefix
  port                 = var.load_balancer.container_port
  protocol             = var.load_balancer.protocol
  vpc_id               = var.load_balancer.vpc_id
  target_type          = "ip"
  deregistration_delay = var.load_balancer.deregistration_delay

  health_check {
    enabled             = true
    path                = var.load_balancer.health_check.path
    matcher             = var.load_balancer.health_check.matcher
    port                = var.load_balancer.health_check.port
    protocol            = var.load_balancer.health_check.protocol
    healthy_threshold   = var.load_balancer.health_check.healthy_threshold
    unhealthy_threshold = var.load_balancer.health_check.unhealthy_threshold
    timeout             = var.load_balancer.health_check.timeout
    interval            = var.load_balancer.health_check.interval
  }

  tags = { Name = local.prefix }

  lifecycle {
    precondition {
      condition     = length(local.prefix) <= 32
      error_message = "The target group name (<Environment>-<name>, \"${local.prefix}\", ${length(local.prefix)} characters) must be 32 characters or fewer. Shorten name or Environment."
    }
  }
}

resource "aws_lb_listener_rule" "this" {
  count = local.lb_enabled ? 1 : 0

  listener_arn = var.load_balancer.listener_arn
  priority     = var.load_balancer.priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[0].arn
  }

  dynamic "condition" {
    for_each = length(var.load_balancer.host_headers) > 0 ? [var.load_balancer.host_headers] : []
    content {
      host_header {
        values = condition.value
      }
    }
  }

  dynamic "condition" {
    for_each = length(var.load_balancer.path_patterns) > 0 ? [var.load_balancer.path_patterns] : []
    content {
      path_pattern {
        values = condition.value
      }
    }
  }

  tags = { Name = local.prefix }
}
