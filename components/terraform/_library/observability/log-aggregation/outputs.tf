output "central_log_group_name" {
  description = "Name of the central log group"
  value       = aws_cloudwatch_log_group.central.name
}

output "central_log_group_arn" {
  description = "ARN of the central log group"
  value       = aws_cloudwatch_log_group.central.arn
}

output "service_log_group_names" {
  description = "Map of service names to log group names"
  value       = { for k, v in aws_cloudwatch_log_group.services : k => v.name }
}

output "service_log_group_arns" {
  description = "Map of service names to log group ARNs"
  value       = { for k, v in aws_cloudwatch_log_group.services : k => v.arn }
}

output "kinesis_stream_name" {
  description = "Name of the Kinesis stream"
  value       = var.enable_kinesis_streaming ? aws_kinesis_stream.logs[0].name : null
}

output "kinesis_stream_arn" {
  description = "ARN of the Kinesis stream"
  value       = var.enable_kinesis_streaming ? aws_kinesis_stream.logs[0].arn : null
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket for log exports"
  value       = var.enable_s3_export ? aws_s3_bucket.logs[0].id : null
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for log exports"
  value       = var.enable_s3_export ? aws_s3_bucket.logs[0].arn : null
}

output "athena_workgroup_name" {
  description = "Name of the Athena workgroup"
  value       = var.enable_athena_queries ? aws_athena_workgroup.logs[0].name : null
}

output "athena_database_name" {
  description = "Name of the Athena database"
  value       = var.enable_athena_queries ? aws_athena_database.logs[0].name : null
}

output "export_lambda_function_name" {
  description = "Name of the export Lambda function"
  value       = var.enable_s3_export ? aws_lambda_function.export_to_s3[0].function_name : null
}

output "metric_filter_names" {
  description = "Names of created metric filters"
  value = concat(
    var.create_error_metric_filter ? [aws_cloudwatch_log_metric_filter.error_count[0].name] : [],
    [for k, v in aws_cloudwatch_log_metric_filter.custom : v.name]
  )
}

output "cloudwatch_logs_insights_query" {
  description = "Sample CloudWatch Logs Insights query"
  value       = "fields @timestamp, @message | sort @timestamp desc | limit 20"
}

output "athena_sample_query" {
  description = "Sample Athena query for log analysis"
  value       = var.enable_athena_queries ? "SELECT * FROM ${aws_athena_database.logs[0].name}.logs LIMIT 10" : null
}

output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown"
  value = {
    cloudwatch_logs = "~$0.50 per GB ingested"
    kinesis_stream  = var.enable_kinesis_streaming ? "~$0.015 per shard hour + $0.014 per GB" : "Not enabled"
    s3_storage      = var.enable_s3_export ? "~$0.023 per GB (Standard), transitions to cheaper storage" : "Not enabled"
    athena_queries  = var.enable_athena_queries ? "~$5 per TB scanned" : "Not enabled"
  }
}
