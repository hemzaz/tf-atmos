output "ssoadmin_instance_arn" {
  value       = one(data.aws_ssoadmin_instances.this.arns)
  description = "ARN of the AWS IAM Identity Center (SSO) instance"
}

output "identity_store_id" {
  value       = one(data.aws_ssoadmin_instances.this.identity_store_ids)
  description = "ID of the Identity Store associated with the SSO instance"
}

output "permission_sets" {
  value       = module.permission_sets.permission_sets
  description = "Permission sets"
}

output "sso_account_assignments" {
  value       = module.sso_account_assignments.assignments
  description = "SSO account assignments"
}

output "group_ids" {
  value = merge(
    { for group_key, group_output in aws_identitystore_group.manual : group_key => group_output.group_id },
    { for group_key, group_output in data.aws_identitystore_group.idp : group_key => group_output.group_id }
  )
  description = "Group IDs for Identity Center (includes both manually created and IdP-synced groups)"
}

output "group_map" {
  value = merge(
    { for group_key, group_output in aws_identitystore_group.manual : group_output.display_name => group_output.group_id },
    { for group_key, group_output in data.aws_identitystore_group.idp : group_output.display_name => group_output.group_id }
  )
  description = "Map of group display name to group ID"
}

output "user_map" {
  value       = { for user_key, user_output in data.aws_identitystore_user.this : user_key => user_output.user_id }
  description = "Map of user name to user ID"
}
