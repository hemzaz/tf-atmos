output "guardduty_detector_id" {
  description = "GuardDuty detector ID"
  value       = var.enable_guardduty ? aws_guardduty_detector.main.id : null
}

output "security_hub_account_arn" {
  description = "Security Hub account ARN"
  value       = var.enable_security_hub ? aws_securityhub_account.main[0].arn : null
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
  value       = var.enable_guardduty ? aws_cloudwatch_event_rule.guardduty_findings[0].arn : null
}

output "securityhub_event_rule_arn" {
  description = "EventBridge rule ARN for Security Hub findings"
  value       = var.enable_security_hub ? aws_cloudwatch_event_rule.securityhub_findings[0].arn : null
}

output "inspector_event_rule_arn" {
  description = "EventBridge rule ARN for Inspector findings"
  value       = var.enable_inspector ? aws_cloudwatch_event_rule.inspector_findings[0].arn : null
}
