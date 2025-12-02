output "vault_id" {
  description = "ID of the backup vault"
  value       = aws_backup_vault.this.id
}

output "vault_arn" {
  description = "ARN of the backup vault"
  value       = aws_backup_vault.this.arn
}

output "vault_name" {
  description = "Name of the backup vault"
  value       = aws_backup_vault.this.name
}

output "vault_recovery_points" {
  description = "Number of recovery points in the vault"
  value       = aws_backup_vault.this.recovery_points
}

output "kms_key_id" {
  description = "ID of the KMS key used for encryption"
  value       = var.kms_key_id != null ? var.kms_key_id : aws_kms_key.backup[0].id
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for encryption"
  value       = var.kms_key_id != null ? var.kms_key_id : aws_kms_key.backup[0].arn
}

output "backup_role_arn" {
  description = "ARN of the IAM role for AWS Backup"
  value       = aws_iam_role.backup.arn
}

output "backup_role_name" {
  description = "Name of the IAM role for AWS Backup"
  value       = aws_iam_role.backup.name
}

output "backup_plan_ids" {
  description = "Map of backup plan names to IDs"
  value       = { for k, v in aws_backup_plan.this : k => v.id }
}

output "backup_plan_arns" {
  description = "Map of backup plan names to ARNs"
  value       = { for k, v in aws_backup_plan.this : k => v.arn }
}

output "backup_selection_ids" {
  description = "Map of backup selection names to IDs"
  value       = { for k, v in aws_backup_selection.this : k => v.id }
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for notifications"
  value       = var.enable_notifications ? aws_sns_topic.backup_notifications[0].arn : null
}

output "vault_lock_configuration" {
  description = "Vault lock configuration details"
  value = var.enable_vault_lock ? {
    changeable_for_days = var.vault_lock_changeable_days
    max_retention_days  = var.vault_lock_max_retention_days
    min_retention_days  = var.vault_lock_min_retention_days
  } : null
}
