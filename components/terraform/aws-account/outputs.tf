output "account_id" {
  value       = one(aws_organizations_account.this[*].id)
  description = "The ID of the AWS account"
}

output "account_arn" {
  value       = one(aws_organizations_account.this[*].arn)
  description = "The ARN of the AWS account"
}

output "account_name" {
  value       = one(aws_organizations_account.this[*].name)
  description = "The name of the AWS account"
}

output "account_email" {
  value       = one(aws_organizations_account.this[*].email)
  description = "The email of the AWS account"
}

output "parent_id" {
  value       = var.parent_id
  description = "The parent ID of the account"
}

output "govcloud_id" {
  value       = var.create_govcloud ? one(aws_organizations_account.this[*].govcloud_id) : null
  description = "ID for a GovCloud account created with the account"
}
