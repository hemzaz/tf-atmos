output "stream_id" {
  description = "Kinesis stream ID"
  value       = aws_kinesis_stream.main.id
}

output "stream_name" {
  description = "Kinesis stream name"
  value       = aws_kinesis_stream.main.name
}

output "stream_arn" {
  description = "Kinesis stream ARN"
  value       = aws_kinesis_stream.main.arn
}

output "shard_count" {
  description = "Current number of shards"
  value       = aws_kinesis_stream.main.shard_count
}

output "retention_period" {
  description = "Data retention period in hours"
  value       = aws_kinesis_stream.main.retention_period
}

output "stream_mode" {
  description = "Stream capacity mode"
  value       = var.stream_mode
}

output "enhanced_fanout_consumers" {
  description = "Map of enhanced fan-out consumer ARNs"
  value = {
    for k, v in aws_kinesis_stream_consumer.main : k => v.arn
  }
}

output "lambda_event_source_mappings" {
  description = "Map of Lambda event source mapping UUIDs"
  value = {
    for k, v in aws_lambda_event_source_mapping.consumer : k => v.uuid
  }
}

output "cloudwatch_log_group_name" {
  description = "CloudWatch log group name"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.stream[0].name : null
}

output "cloudwatch_log_group_arn" {
  description = "CloudWatch log group ARN"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.stream[0].arn : null
}

output "alarm_arns" {
  description = "Map of CloudWatch alarm ARNs"
  value = merge(
    var.enable_monitoring ? { iterator_age = aws_cloudwatch_metric_alarm.iterator_age[0].arn } : {},
    var.enable_monitoring && var.stream_mode == "PROVISIONED" ? {
      write_throttle = aws_cloudwatch_metric_alarm.write_throttle[0].arn
      read_throttle  = aws_cloudwatch_metric_alarm.read_throttle[0].arn
    } : {}
  )
}
