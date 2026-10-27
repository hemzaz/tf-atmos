output "organization_id" {
  value       = try(aws_organizations_organization.this[0].id, null)
  description = "The ID of the organization"
}

output "organization_arn" {
  value       = try(aws_organizations_organization.this[0].arn, null)
  description = "The ARN of the organization"
}

output "organization_root_id" {
  value       = try(aws_organizations_organization.this[0].roots[0].id, null)
  description = "The ID of the organization root"
}

output "master_account_id" {
  value       = try(aws_organizations_organization.this[0].master_account_id, null)
  description = "The ID of the master account"
}

output "master_account_arn" {
  value       = try(aws_organizations_organization.this[0].master_account_arn, null)
  description = "The ARN of the master account"
}

output "master_account_email" {
  value       = try(aws_organizations_organization.this[0].master_account_email, null)
  description = "The email of the master account"
}

output "non_master_accounts" {
  value       = try(aws_organizations_organization.this[0].non_master_accounts, [])
  description = "List of non-master accounts in the organization"
}

output "roots" {
  value       = try(aws_organizations_organization.this[0].roots, [])
  description = "List of organization roots"
}

output "organization_enabled_features" {
  value       = try(aws_iam_organizations_features.this[0].enabled_features, [])
  description = "List of enabled IAM organization features"
}
