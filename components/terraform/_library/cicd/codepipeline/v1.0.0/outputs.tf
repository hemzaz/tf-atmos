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
  value       = length(aws_s3_bucket.artifact) > 0 ? aws_s3_bucket.artifact[0].id : var.artifact_bucket_name
}

output "artifact_bucket_arn" {
  description = "ARN of the S3 artifact bucket"
  value       = length(aws_s3_bucket.artifact) > 0 ? aws_s3_bucket.artifact[0].arn : "arn:${data.aws_partition.current.partition}:s3:::${var.artifact_bucket_name}"
}

################################################################################
# CloudWatch Event Rule Outputs
################################################################################

output "notification_event_rule_arn" {
  description = "ARN of the CloudWatch Event Rule for pipeline notifications"
  value       = var.enable_notifications && var.notification_target_arn != null ? aws_cloudwatch_event_rule.pipeline[0].arn : null
}

output "source_event_rule_arn" {
  description = "ARN of the CloudWatch Event Rule for source changes"
  value       = var.source_provider == "CodeCommit" && local.source_config.detect_changes ? aws_cloudwatch_event_rule.source[0].arn : null
}

################################################################################
# Metadata Outputs
################################################################################

output "pipeline_url" {
  description = "URL to the CodePipeline console"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/codesuite/codepipeline/pipelines/${aws_codepipeline.this.name}/view"
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
