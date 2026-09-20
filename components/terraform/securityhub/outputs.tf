output "account_id" {
  description = "AWS account ID Security Hub is enabled in (null when enable is false)"
  value       = var.enable ? aws_securityhub_account.main[0].id : null
}

output "account_arn" {
  description = "ARN of the Security Hub account resource (null when enable is false)"
  value       = var.enable ? aws_securityhub_account.main[0].arn : null
}

output "subscribed_standards_arns" {
  description = "ARNs of the explicitly subscribed standards; excludes the defaults Security Hub enables on its own"
  value       = [for subscription in aws_securityhub_standards_subscription.main : subscription.standards_arn]
}
