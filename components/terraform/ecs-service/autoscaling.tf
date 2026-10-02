# Optional target-tracking autoscaling of the service's desired count. Cloud
# Posse's aws-ecs-service scales with step policies on CloudWatch alarms
# (autoscaling_dimension, cpu/memory_utilization_high/low_*); target tracking
# needs no alarms of its own and also covers ALB requests per target, so this
# component uses it instead.

locals {
  # ALBRequestCountPerTarget's resource label: app/<lb>/<id>/targetgroup/<tg>/<id>.
  # The load balancer part is the listener ARN's app/<lb>/<id>.
  alb_arn_suffix = local.lb_enabled ? join("/", slice(split("/", split(":listener/", var.load_balancer.listener_arn)[1]), 0, 3)) : null

  autoscaling_policies = local.autoscaling_enabled ? {
    for k, p in {
      cpu = var.autoscaling.cpu_utilization_target == null ? null : {
        metric = "ECSServiceAverageCPUUtilization", target = var.autoscaling.cpu_utilization_target, label = null
      }
      memory = var.autoscaling.memory_utilization_target == null ? null : {
        metric = "ECSServiceAverageMemoryUtilization", target = var.autoscaling.memory_utilization_target, label = null
      }
      alb-requests = var.autoscaling.alb_request_count_per_target == null ? null : {
        metric = "ALBRequestCountPerTarget", target = var.autoscaling.alb_request_count_per_target, label = "lb"
      }
    } : k => p if p != null
  } : {}
}

resource "aws_appautoscaling_target" "this" {
  count = local.autoscaling_enabled ? 1 : 0

  service_namespace  = "ecs"
  scalable_dimension = "ecs:service:DesiredCount"
  resource_id        = "service/${local.cluster_name}/${aws_ecs_service.autoscaled[0].name}"
  min_capacity       = var.autoscaling.min_capacity
  max_capacity       = var.autoscaling.max_capacity

  tags = { Name = local.prefix }
}

resource "aws_appautoscaling_policy" "this" {
  for_each = local.autoscaling_policies

  name               = "${local.prefix}-${each.key}"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.this[0].service_namespace
  scalable_dimension = aws_appautoscaling_target.this[0].scalable_dimension
  resource_id        = aws_appautoscaling_target.this[0].resource_id

  target_tracking_scaling_policy_configuration {
    target_value       = each.value.target
    scale_in_cooldown  = var.autoscaling.scale_in_cooldown
    scale_out_cooldown = var.autoscaling.scale_out_cooldown

    predefined_metric_specification {
      predefined_metric_type = each.value.metric
      resource_label         = each.value.label == null ? null : "${local.alb_arn_suffix}/${aws_lb_target_group.this[0].arn_suffix}"
    }
  }
}
