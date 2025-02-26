output "log_group_names" {
  value       = { for k, v in aws_cloudwatch_log_group.main : k => v.name }
  description = "Map of log group names"
}

output "log_group_arns" {
  value       = { for k, v in aws_cloudwatch_log_group.main : k => v.arn }
  description = "Map of log group ARNs"
}

output "dashboard_name" {
  value       = var.create_dashboard ? aws_cloudwatch_dashboard.main[0].dashboard_name : null
  description = "Name of the CloudWatch dashboard"
}

output "sns_topic_arn" {
  value       = var.create_sns_topic ? aws_sns_topic.alarms[0].arn : null
  description = "ARN of the SNS topic for alarms"
}

output "cpu_alarm_names" {
  value       = { for k, v in aws_cloudwatch_metric_alarm.cpu_high : k => v.alarm_name }
  description = "Map of CPU alarm names"
}

output "memory_alarm_names" {
  value       = { for k, v in aws_cloudwatch_metric_alarm.memory_high : k => v.alarm_name }
  description = "Map of memory alarm names"
}

output "db_connection_alarm_names" {
  value       = { for k, v in aws_cloudwatch_metric_alarm.db_connections_high : k => v.alarm_name }
  description = "Map of database connection alarm names"
}

output "lambda_error_alarm_names" {
  value       = { for k, v in aws_cloudwatch_metric_alarm.lambda_errors : k => v.alarm_name }
  description = "Map of Lambda error alarm names"
}