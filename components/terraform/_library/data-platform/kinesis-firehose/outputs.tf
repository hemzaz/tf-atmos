output "delivery_stream_id" {
  description = "Firehose delivery stream ID"
  value       = aws_kinesis_firehose_delivery_stream.main.id
}

output "delivery_stream_name" {
  description = "Firehose delivery stream name"
  value       = aws_kinesis_firehose_delivery_stream.main.name
}

output "delivery_stream_arn" {
  description = "Firehose delivery stream ARN"
  value       = aws_kinesis_firehose_delivery_stream.main.arn
}

output "iam_role_arn" {
  description = "Firehose IAM role ARN"
  value       = aws_iam_role.firehose.arn
}

output "iam_role_name" {
  description = "Firehose IAM role name"
  value       = aws_iam_role.firehose.name
}

output "cloudwatch_log_group_name" {
  description = "CloudWatch log group name"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.firehose[0].name : null
}

output "cloudwatch_log_group_arn" {
  description = "CloudWatch log group ARN"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.firehose[0].arn : null
}

output "alarm_arns" {
  description = "Map of CloudWatch alarm ARNs"
  value = var.enable_monitoring ? {
    delivery_failed = aws_cloudwatch_metric_alarm.delivery_to_s3_failed[0].arn
    throttled       = aws_cloudwatch_metric_alarm.throttled_records[0].arn
  } : {}
}
