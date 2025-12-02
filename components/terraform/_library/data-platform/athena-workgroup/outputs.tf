output "workgroup_id" {
  description = "Athena workgroup ID"
  value       = aws_athena_workgroup.main.id
}

output "workgroup_name" {
  description = "Athena workgroup name"
  value       = aws_athena_workgroup.main.name
}

output "workgroup_arn" {
  description = "Athena workgroup ARN"
  value       = aws_athena_workgroup.main.arn
}

output "workgroup_state" {
  description = "Athena workgroup state"
  value       = aws_athena_workgroup.main.state
}

output "named_query_ids" {
  description = "Map of named query IDs"
  value = {
    for k, v in aws_athena_named_query.main : k => v.id
  }
}

output "data_catalog_arns" {
  description = "Map of data catalog ARNs"
  value = {
    for k, v in aws_athena_data_catalog.main : k => v.arn
  }
}

output "prepared_statement_names" {
  description = "Map of prepared statement names"
  value = {
    for k, v in aws_athena_prepared_statement.main : k => v.name
  }
}

output "cloudwatch_log_group_name" {
  description = "CloudWatch log group name"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.workgroup[0].name : null
}

output "cloudwatch_log_group_arn" {
  description = "CloudWatch log group ARN"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.workgroup[0].arn : null
}

output "iam_policy_arn" {
  description = "IAM policy ARN for workgroup access"
  value       = var.create_iam_policy ? aws_iam_policy.workgroup_access[0].arn : null
}

output "iam_policy_name" {
  description = "IAM policy name for workgroup access"
  value       = var.create_iam_policy ? aws_iam_policy.workgroup_access[0].name : null
}

output "alarm_arns" {
  description = "Map of CloudWatch alarm ARNs"
  value = merge(
    var.enable_monitoring ? {
      query_execution_time = aws_cloudwatch_metric_alarm.query_execution_time[0].arn
      data_scanned         = aws_cloudwatch_metric_alarm.data_scanned[0].arn
      query_planning_time  = aws_cloudwatch_metric_alarm.query_planning_time[0].arn
    } : {},
    var.enable_cost_control ? {
      cost_control = aws_cloudwatch_metric_alarm.cost_control[0].arn
    } : {}
  )
}
