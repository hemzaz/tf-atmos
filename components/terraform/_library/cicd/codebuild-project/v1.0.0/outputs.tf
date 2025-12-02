################################################################################
# Project Outputs
################################################################################

output "project_id" {
  description = "ID of the CodeBuild project"
  value       = aws_codebuild_project.this.id
}

output "project_arn" {
  description = "ARN of the CodeBuild project"
  value       = aws_codebuild_project.this.arn
}

output "project_name" {
  description = "Name of the CodeBuild project"
  value       = aws_codebuild_project.this.name
}

################################################################################
# IAM Role Outputs
################################################################################

output "role_arn" {
  description = "ARN of the CodeBuild IAM role"
  value       = var.create_role ? aws_iam_role.this[0].arn : var.role_arn
}

output "role_id" {
  description = "ID of the CodeBuild IAM role"
  value       = var.create_role ? aws_iam_role.this[0].id : null
}

output "role_name" {
  description = "Name of the CodeBuild IAM role"
  value       = var.create_role ? aws_iam_role.this[0].name : null
}

################################################################################
# CloudWatch Logs Outputs
################################################################################

output "cloudwatch_logs_group_name" {
  description = "Name of the CloudWatch Logs group"
  value       = var.enable_cloudwatch_logs ? local.cloudwatch_logs_group_name : null
}

output "cloudwatch_logs_group_arn" {
  description = "ARN of the CloudWatch Logs group"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.this[0].arn : null
}

################################################################################
# Webhook Outputs
################################################################################

output "webhook_url" {
  description = "URL for the webhook"
  value       = var.enable_webhook ? aws_codebuild_webhook.this[0].payload_url : null
}

output "webhook_secret" {
  description = "Secret token for the webhook"
  value       = var.enable_webhook ? aws_codebuild_webhook.this[0].secret : null
  sensitive   = true
}

################################################################################
# Metadata Outputs
################################################################################

output "project_url" {
  description = "URL to the CodeBuild project console"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/codesuite/codebuild/projects/${aws_codebuild_project.this.name}"
}

output "badge_url" {
  description = "Build badge URL"
  value       = aws_codebuild_project.this.badge_url
}
