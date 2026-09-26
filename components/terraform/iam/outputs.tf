output "cross_account_role_arn" {
  description = "ARN of the cross-account IAM role"
  value       = one(aws_iam_role.cross_account_role[*].arn)
}

output "cross_account_role_name" {
  description = "Name of the cross-account IAM role"
  value       = one(aws_iam_role.cross_account_role[*].name)
}

output "cross_account_policy_arn" {
  description = "ARN of the cross-account IAM policy"
  value       = one(aws_iam_policy.cross_account_policy[*].arn)
}

output "cross_account_policy_name" {
  description = "Name of the cross-account IAM policy"
  value       = one(aws_iam_policy.cross_account_policy[*].name)
}

output "github_oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC provider the CI roles trust"
  value       = var.github_oidc_enabled ? local.github_oidc_provider_arn : null
}

output "ci_plan_role_arn" {
  description = "ARN of the read-only GitHub Actions plan role; set it as the repository variable AWS_PLAN_ROLE_ARN"
  value       = one(aws_iam_role.ci_plan[*].arn)
}

output "ci_plan_role_name" {
  description = "Name of the read-only GitHub Actions plan role"
  value       = one(aws_iam_role.ci_plan[*].name)
}

output "ci_apply_role_arn" {
  description = "ARN of the GitHub Actions apply role; set it as AWS_ROLE_ARN on each stack's GitHub Environment"
  value       = one(aws_iam_role.ci_apply[*].arn)
}

output "ci_apply_role_name" {
  description = "Name of the GitHub Actions apply role"
  value       = one(aws_iam_role.ci_apply[*].name)
}

output "autoscaling_service_linked_role_arn" {
  description = "ARN of the AWS Auto Scaling service-linked role, whether created here or already present in the account. kms/main depends on this component so its allow_autoscaling_ebs key-policy grant names a principal that exists."
  # aws_iam_roles.arns is a set(string), which has no index; tolist() first.
  value = length(aws_iam_service_linked_role.autoscaling) > 0 ? aws_iam_service_linked_role.autoscaling[0].arn : try(tolist(data.aws_iam_roles.existing_autoscaling_slr.arns)[0], null)
}
