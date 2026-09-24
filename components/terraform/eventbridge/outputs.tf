# The first four are Cloud Posse's aws-eventbridge outputs.

output "cloudwatch_logs_log_group_arn" {
  description = "The ARN of the CloudWatch Log Group"
  value       = one(aws_cloudwatch_log_group.this[*].arn)
}

output "cloudwatch_logs_log_group_name" {
  description = "The name of the CloudWatch Log Group"
  value       = one(aws_cloudwatch_log_group.this[*].name)
}

output "cloudwatch_event_rule_arn" {
  description = "The ARN of the CloudWatch Event Rule"
  value       = one(aws_cloudwatch_event_rule.this[*].arn)
}

output "cloudwatch_event_rule_name" {
  description = "The name of the CloudWatch Event Rule"
  value       = one(aws_cloudwatch_event_rule.this[*].name)
}

output "event_bus_name" {
  description = "Name of the bus the rule sits on: the created bus, or event_bus_name (null when disabled)"
  value       = local.enabled ? local.event_bus_name : null
}

output "event_bus_arn" {
  description = "ARN of the created event bus (null unless create_event_bus)"
  value       = one(aws_cloudwatch_event_bus.this[*].arn)
}

output "event_archive_arn" {
  description = "ARN of the event archive (null unless archive_enabled)"
  value       = one(aws_cloudwatch_event_archive.this[*].arn)
}
