output "guardduty_detector_id" {
  description = "GuardDuty detector ID this component routes findings for (owned by the guardduty component)"
  value       = var.guardduty_detector_id
}

output "security_hub_account_arn" {
  description = "Security Hub hub ARN this component routes findings for (owned by the securityhub component)"
  value       = var.securityhub_account_arn
}

output "security_alerts_topic_arn" {
  description = "SNS topic ARN for security alerts"
  value       = aws_sns_topic.security_alerts.arn
}

output "alert_enrichment_function_arn" {
  description = "Lambda function ARN for alert enrichment"
  value       = var.enable_alert_enrichment ? aws_lambda_function.alert_enrichment[0].arn : null
}

output "guardduty_event_rule_arn" {
  description = "EventBridge rule ARN for GuardDuty findings"
  value       = local.guardduty_enabled ? aws_cloudwatch_event_rule.guardduty_findings[0].arn : null
}

output "securityhub_event_rule_arn" {
  description = "EventBridge rule ARN for Security Hub findings"
  value       = local.security_hub_enabled ? aws_cloudwatch_event_rule.securityhub_findings[0].arn : null
}

output "inspector_event_rule_arn" {
  description = "EventBridge rule ARN for Inspector findings"
  value       = var.enable_inspector ? aws_cloudwatch_event_rule.inspector_findings[0].arn : null
}

output "cloudtrail_metric_filter_names" {
  description = "Names of the CIS metric filters on the CloudTrail log group, by filter key"
  value       = { for k, f in aws_cloudwatch_log_metric_filter.cloudtrail : k => f.name }
}
