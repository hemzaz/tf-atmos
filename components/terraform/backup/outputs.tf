output "backup_vault_id" {
  description = "ID of the backup vault"
  value       = aws_backup_vault.main.id
}

output "backup_vault_arn" {
  description = "ARN of the backup vault"
  value       = aws_backup_vault.main.arn
}

output "backup_vault_recovery_points" {
  description = "Number of recovery points in the backup vault"
  value       = aws_backup_vault.main.recovery_points
}

output "cross_region_vault_arn" {
  description = "ARN of the cross-region backup vault"
  value       = var.enable_cross_region_backup ? aws_backup_vault.cross_region[0].arn : null
}

output "daily_backup_plan_id" {
  description = "ID of the daily backup plan"
  value       = aws_backup_plan.daily.id
}

output "daily_backup_plan_arn" {
  description = "ARN of the daily backup plan"
  value       = aws_backup_plan.daily.arn
}

output "weekly_backup_plan_id" {
  description = "ID of the weekly backup plan"
  value       = aws_backup_plan.weekly.id
}

output "monthly_backup_plan_id" {
  description = "ID of the monthly backup plan"
  value       = aws_backup_plan.monthly.id
}

output "backup_role_arn" {
  description = "ARN of the IAM role used by AWS Backup"
  value       = aws_iam_role.backup.arn
}

output "backup_notifications_topic_arn" {
  description = "ARN of the SNS topic for backup notifications"
  value       = var.enable_backup_notifications ? aws_sns_topic.backup_notifications[0].arn : null
}

output "backup_testing_function_arn" {
  description = "ARN of the backup testing Lambda function"
  value       = var.enable_backup_testing ? aws_lambda_function.backup_testing[0].arn : null
}
