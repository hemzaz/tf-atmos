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
  description = "ARN of the AWS Auto Scaling service-linked role created by this instance, or null when enable_autoscaling_service_linked_role is false"
  value       = one(aws_iam_service_linked_role.autoscaling[*].arn)
}
