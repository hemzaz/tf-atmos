output "lambda_uploader_role_arn" {
  description = "ARN of the GitHub Actions role application CI assumes to upload Lambda packages to this stage's s3/lambda-artifacts bucket, or null when lambda_uploader_trusted_github_repos is empty"
  value       = one(aws_iam_role.lambda_uploader[*].arn)
}

output "lambda_artifacts_bucket_name" {
  description = "The s3/lambda-artifacts bucket the uploader role may write (<Environment>-lambda-artifacts-<account id>), or null when the role is not created"
  value       = local.create_lambda_uploader_role ? local.lambda_artifacts_bucket_name : null
}
