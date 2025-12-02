output "sns_topic_arn" {
  description = "ARN of the SNS topic for alarms"
  value       = var.create_sns_topic ? aws_sns_topic.alarms[0].arn : null
}

output "sns_topic_name" {
  description = "Name of the SNS topic for alarms"
  value       = var.create_sns_topic ? aws_sns_topic.alarms[0].name : null
}

output "cpu_alarm_arn" {
  description = "ARN of the CPU high alarm"
  value       = var.create_cpu_alarms ? aws_cloudwatch_metric_alarm.cpu_high[0].arn : null
}

output "memory_alarm_arn" {
  description = "ARN of the memory high alarm"
  value       = var.create_memory_alarms ? aws_cloudwatch_metric_alarm.memory_high[0].arn : null
}

output "disk_alarm_arn" {
  description = "ARN of the disk high alarm"
  value       = var.create_disk_alarms ? aws_cloudwatch_metric_alarm.disk_high[0].arn : null
}

output "anomaly_alarm_arn" {
  description = "ARN of the anomaly detection alarm"
  value       = var.enable_anomaly_detection ? aws_cloudwatch_metric_alarm.anomaly_cpu[0].arn : null
}

output "composite_alarm_arn" {
  description = "ARN of the composite alarm"
  value       = var.create_composite_alarms ? aws_cloudwatch_composite_alarm.system_critical[0].arn : null
}

output "custom_alarm_arns" {
  description = "ARNs of custom alarms"
  value       = { for k, v in aws_cloudwatch_metric_alarm.custom : k => v.arn }
}

output "auto_remediation_function_arn" {
  description = "ARN of the auto-remediation Lambda function"
  value       = var.enable_auto_remediation ? aws_lambda_function.auto_remediation[0].arn : null
}

output "alarm_count" {
  description = "Total number of alarms created"
  value = (
    (var.create_cpu_alarms ? 1 : 0) +
    (var.create_memory_alarms ? 1 : 0) +
    (var.create_disk_alarms ? 1 : 0) +
    (var.enable_anomaly_detection ? 1 : 0) +
    length(var.custom_alarms)
  )
}
