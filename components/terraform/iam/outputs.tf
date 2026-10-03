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
  description = "ARN of the read-only GitHub Actions plan role (CI derives the same ARN per stack with ci-apply-role-arn.py --kind plan; no repository variable holds it)"
  value       = one(aws_iam_role.ci_plan[*].arn)
}

output "ci_plan_role_name" {
  description = "Name of the read-only GitHub Actions plan role"
  value       = one(aws_iam_role.ci_plan[*].name)
}

output "ci_apply_role_arn" {
  description = "ARN of the GitHub Actions apply role (terraform-cd.yml derives the same ARN from this instance's config; no GitHub Environment is used)"
  value       = one(aws_iam_role.ci_apply[*].arn)
}

output "ci_apply_role_name" {
  description = "Name of the GitHub Actions apply role"
  value       = one(aws_iam_role.ci_apply[*].name)
}

output "lambda_uploader_role_arn" {
  description = "ARN of the GitHub Actions role application CI assumes to upload Lambda packages to this stage's s3/lambda-artifacts bucket, or null when lambda_uploader_trusted_github_repos is empty"
  value       = one(aws_iam_role.lambda_uploader[*].arn)
}

output "lambda_artifacts_bucket_name" {
  description = "The s3/lambda-artifacts bucket the uploader role may write (<Environment>-lambda-artifacts-<account id>), or null when the role is not created"
  value       = local.create_lambda_uploader_role ? local.lambda_artifacts_bucket_name : null
}

output "autoscaling_service_linked_role_arn" {
  description = "ARN of the AWS Auto Scaling service-linked role created by this instance, or null when enable_autoscaling_service_linked_role is false"
  value       = one(aws_iam_service_linked_role.autoscaling[*].arn)
}
