################################################################################
# Pipeline Outputs
################################################################################

output "pipeline_id" {
  description = "ID of the CodePipeline"
  value       = aws_codepipeline.this.id
}

output "pipeline_arn" {
  description = "ARN of the CodePipeline"
  value       = aws_codepipeline.this.arn
}

output "pipeline_name" {
  description = "Name of the CodePipeline"
  value       = aws_codepipeline.this.name
}

################################################################################
# IAM Role Outputs
################################################################################

output "pipeline_role_arn" {
  description = "ARN of the pipeline IAM role"
  value       = var.create_role ? aws_iam_role.pipeline[0].arn : var.role_arn
}

output "pipeline_role_id" {
  description = "ID of the pipeline IAM role"
  value       = var.create_role ? aws_iam_role.pipeline[0].id : null
}

output "pipeline_role_name" {
  description = "Name of the pipeline IAM role"
  value       = var.create_role ? aws_iam_role.pipeline[0].name : null
}

################################################################################
# S3 Artifact Store Outputs
################################################################################

output "artifact_bucket_id" {
  description = "ID of the S3 artifact bucket"
  value       = var.create_artifact_bucket ? aws_s3_bucket.artifact[0].id : data.aws_s3_bucket.artifact[0].id
}

output "artifact_bucket_arn" {
  description = "ARN of the S3 artifact bucket"
  value       = var.create_artifact_bucket ? aws_s3_bucket.artifact[0].arn : data.aws_s3_bucket.artifact[0].arn
}

################################################################################
# CloudWatch Event Rule Outputs
################################################################################

output "notification_event_rule_arn" {
  description = "ARN of the CloudWatch Event Rule for pipeline notifications"
  value       = one(aws_cloudwatch_event_rule.pipeline[*].arn)
}

output "source_event_rule_arn" {
  description = "ARN of the CloudWatch Event Rule for source changes"
  value       = one(aws_cloudwatch_event_rule.source[*].arn)
}

################################################################################
# Metadata Outputs
################################################################################

output "pipeline_url" {
  description = "URL to the CodePipeline console"
  value       = "https://${data.aws_region.current.region}.console.aws.amazon.com/codesuite/codepipeline/pipelines/${aws_codepipeline.this.name}/view"
}

output "source_provider" {
  description = "Source provider type"
  value       = var.source_provider
}

output "deploy_provider" {
  description = "Deploy provider type"
  value       = var.deploy_provider
}

output "pipeline_type" {
  description = "Pipeline type (V1 or V2)"
  value       = var.pipeline_type
}
