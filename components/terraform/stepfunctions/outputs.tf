output "state_machine_arn" {
  description = "State machine ARN"
  value       = one(aws_sfn_state_machine.this[*].arn)
}

output "state_machine_name" {
  description = "State machine name"
  value       = one(aws_sfn_state_machine.this[*].name)
}

output "role_arn" {
  description = "Execution role ARN"
  value       = one(aws_iam_role.this[*].arn)
}

output "events_role_arn" {
  description = "EventBridge invoke role ARN (null unless events_role_enabled); allowed states:StartExecution on this state machine only"
  value       = one(aws_iam_role.events[*].arn)
}

output "log_group_name" {
  description = "CloudWatch Logs log group name (/aws/vendedlogs/states/<Environment>-<name>)"
  value       = one(aws_cloudwatch_log_group.this[*].name)
}
