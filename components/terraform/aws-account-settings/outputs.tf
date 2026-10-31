output "account_alias" {
  value       = try(aws_iam_account_alias.this[0].account_alias, null)
  description = "The IAM account alias"
}

output "s3_public_access_block_configured" {
  value       = local.enabled && var.s3_block_public_access_enabled
  description = "Whether S3 public access block was configured"
}

output "ebs_encryption_configured" {
  value       = local.enabled && var.ebs_default_encryption_enabled
  description = "Whether EBS default encryption was configured"
}

output "billing_contact_configured" {
  value       = local.enabled && var.billing_contact != null
  description = "Whether billing contact was configured"
}

output "operations_contact_configured" {
  value       = local.enabled && var.operations_contact != null
  description = "Whether operations contact was configured"
}

output "security_contact_configured" {
  value       = local.enabled && var.security_contact != null
  description = "Whether security contact was configured"
}

output "ssm_block_public_document_sharing_configured" {
  value       = local.enabled && var.ssm_block_public_document_sharing
  description = "Whether SSM block public document sharing was configured"
}

output "ssm_session_preferences_configured" {
  value       = local.enabled && var.ssm_session_preferences_enabled
  description = "Whether SSM Session Manager preferences were configured"
}

output "ssm_session_idle_timeout_minutes" {
  value       = var.ssm_session_preferences_enabled ? var.ssm_session_idle_timeout_minutes : null
  description = "The configured SSM session idle timeout in minutes"
}

output "ebs_snapshot_block_public_access_configured" {
  value       = local.enabled && var.ebs_snapshot_block_public_access_enabled
  description = "Whether EBS snapshot block public access was configured"
}

output "ebs_snapshot_block_public_access_state" {
  value       = var.ebs_snapshot_block_public_access_enabled ? var.ebs_snapshot_block_public_access_state : null
  description = "The state of EBS snapshot block public access"
}

output "ec2_instance_metadata_defaults_configured" {
  value       = local.enabled && var.ec2_instance_metadata_defaults_enabled
  description = "Whether EC2 instance metadata defaults were configured"
}

output "ec2_image_block_public_access_configured" {
  value       = local.enabled && var.ec2_image_block_public_access_enabled
  description = "Whether EC2 AMI block public access was configured"
}

output "ec2_image_block_public_access_state" {
  value       = var.ec2_image_block_public_access_enabled ? var.ec2_image_block_public_access_state : null
  description = "The state of EC2 AMI block public access"
}

output "emr_block_public_access_configured" {
  value       = local.enabled && var.emr_block_public_access_enabled
  description = "Whether EMR block public access was configured"
}
