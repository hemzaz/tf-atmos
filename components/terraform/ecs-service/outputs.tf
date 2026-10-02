output "service_name" {
  description = "ECS service name (<Environment>-<name>), for the ServiceName CloudWatch dimension"
  value       = try(local.service.name, null)
}

output "service_arn" {
  description = "ECS service ARN"
  value       = try(local.service.arn, null)
}

output "task_definition_arn" {
  description = "Revisioned task definition ARN (...:task-definition/<family>:<revision>) the service runs"
  value       = one(aws_ecs_task_definition.this[*].arn)
}

output "task_definition_family" {
  description = "Task definition family (<Environment>-<name>)"
  value       = one(aws_ecs_task_definition.this[*].family)
}

output "execution_role_arn" {
  description = "Task execution role: task_exec_role_arn or the created <Environment>-<name>-task-execution (null when disabled)"
  value       = local.enabled ? local.task_exec_role_arn : null
}

output "task_role_arn" {
  description = "Task role: task_role_arn or the created <Environment>-<name>-task; null when the tasks have no task role"
  value       = local.enabled ? local.task_role_arn : null
}

output "target_group_arn" {
  description = "The service's target group ARN (null without load_balancer)"
  value       = one(aws_lb_target_group.this[*].arn)
}

output "target_group_arn_suffix" {
  description = "The service's target group ARN suffix (targetgroup/<name>/<id>), for the TargetGroup CloudWatch dimension (null without load_balancer)"
  value       = one(aws_lb_target_group.this[*].arn_suffix)
}

output "log_group_name" {
  description = "The containers' CloudWatch log group (/ecs/<Environment>-<name>)"
  value       = one(aws_cloudwatch_log_group.this[*].name)
}

output "log_group_arn" {
  description = "The containers' CloudWatch log group ARN"
  value       = one(aws_cloudwatch_log_group.this[*].arn)
}

output "listener_rule_arn" {
  description = "The listener rule forwarding to the service's target group (null without load_balancer)"
  value       = one(aws_lb_listener_rule.this[*].arn)
}
