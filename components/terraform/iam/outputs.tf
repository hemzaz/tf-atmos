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
