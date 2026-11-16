output "security_alerts_topic_arn" {
  description = "SNS topic ARN for security alerts"
  value       = aws_sns_topic.security_alerts.arn
}

output "alert_enrichment_function_arn" {
  description = "Lambda function ARN for alert enrichment"
  value       = var.enable_alert_enrichment ? aws_lambda_function.alert_enrichment[0].arn : null
}

output "guardduty_event_rule_arn" {
  description = "EventBridge rule ARN for GuardDuty findings (null while enable_guardduty_route is false)"
  value       = local.guardduty_enabled ? aws_cloudwatch_event_rule.guardduty_findings[0].arn : null
}

output "securityhub_event_rule_arn" {
  description = "EventBridge rule ARN for Security Hub findings (null while enable_securityhub_route is false)"
  value       = local.security_hub_enabled ? aws_cloudwatch_event_rule.securityhub_findings[0].arn : null
}

output "inspector_event_rule_arn" {
  description = "EventBridge rule ARN for Inspector findings (null while enable_inspector2_route is false)"
  value       = local.inspector_enabled ? aws_cloudwatch_event_rule.inspector_findings[0].arn : null
}

output "security_group_change_rule_arn" {
  description = "EventBridge rule ARN routing security group changes to the alert topic"
  value       = var.enable_security_group_change_events ? aws_cloudwatch_event_rule.security_group_changes[0].arn : null
}

output "cloudtrail_metric_filter_names" {
  description = "Names of the CIS metric filters on the CloudTrail log group, by filter key"
  value       = { for k, f in aws_cloudwatch_log_metric_filter.cloudtrail : k => f.name }
}
