output "domain_id" {
  description = "OpenSearch domain ID"
  value       = aws_opensearch_domain.main.domain_id
}

output "domain_name" {
  description = "OpenSearch domain name"
  value       = aws_opensearch_domain.main.domain_name
}

output "domain_arn" {
  description = "OpenSearch domain ARN"
  value       = aws_opensearch_domain.main.arn
}

output "endpoint" {
  description = "OpenSearch domain endpoint"
  value       = aws_opensearch_domain.main.endpoint
}

output "kibana_endpoint" {
  description = "OpenSearch Dashboards endpoint"
  value       = aws_opensearch_domain.main.dashboard_endpoint
}

output "domain_endpoint_options" {
  description = "Domain endpoint options"
  value       = aws_opensearch_domain.main.domain_endpoint_options
}

output "vpc_options" {
  description = "VPC options"
  value       = aws_opensearch_domain.main.vpc_options
}

output "security_group_id" {
  description = "Security group ID (VPC deployment)"
  value       = var.subnet_ids != null ? aws_security_group.opensearch[0].id : null
}

output "cloudwatch_log_group_arns" {
  description = "Map of CloudWatch log group ARNs"
  value = {
    index_slow_logs  = aws_cloudwatch_log_group.index_slow_logs.arn
    search_slow_logs = aws_cloudwatch_log_group.search_slow_logs.arn
    error_logs       = aws_cloudwatch_log_group.error_logs.arn
    audit_logs       = aws_cloudwatch_log_group.audit_logs.arn
  }
}

output "alarm_arns" {
  description = "Map of CloudWatch alarm ARNs"
  value = var.enable_monitoring ? {
    cluster_red          = aws_cloudwatch_metric_alarm.cluster_red[0].arn
    cluster_yellow       = aws_cloudwatch_metric_alarm.cluster_yellow[0].arn
    free_storage_space   = aws_cloudwatch_metric_alarm.free_storage_space[0].arn
    cpu_utilization      = aws_cloudwatch_metric_alarm.cpu_utilization[0].arn
    jvm_memory_pressure  = aws_cloudwatch_metric_alarm.jvm_memory_pressure[0].arn
  } : {}
}

output "cognito_role_arn" {
  description = "Cognito IAM role ARN"
  value       = var.cognito_user_pool_id != null ? aws_iam_role.cognito[0].arn : null
}
