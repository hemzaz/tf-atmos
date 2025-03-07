# Template: Terraform Component Outputs File
# This template follows the best practices outlined in GUIDELINES.md
# Replace placeholder values and comments with your actual implementation

# PRIMARY RESOURCE OUTPUTS
# Replace with outputs for your primary resource

output "id" {
  description = "ID of the primary resource"
  value       = local.enabled ? aws_example_resource.example[0].id : null
}

output "arn" {
  description = "ARN of the primary resource"
  value       = local.enabled ? aws_example_resource.example[0].arn : null
}

output "name" {
  description = "Name of the primary resource"
  value       = local.enabled ? aws_example_resource.example[0].name : null
}

# ASSOCIATED RESOURCE OUTPUTS
# Replace with outputs for associated resources

output "associated_resource_id" {
  description = "ID of the associated resource"
  value       = local.enabled ? aws_example_associated_resource.example[0].id : null
}

# SECURITY OUTPUTS
# Replace with security-related outputs

output "role_arn" {
  description = "ARN of the IAM role"
  value       = local.enabled ? aws_iam_role.service_role[0].arn : null
}

output "role_name" {
  description = "Name of the IAM role"
  value       = local.enabled ? aws_iam_role.service_role[0].name : null
}

# LOGGING & MONITORING OUTPUTS
# Replace with logging & monitoring outputs

output "log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = local.enabled && var.enable_logging ? aws_cloudwatch_log_group.logs[0].name : null
}

output "log_group_arn" {
  description = "ARN of the CloudWatch log group"
  value       = local.enabled && var.enable_logging ? aws_cloudwatch_log_group.logs[0].arn : null
}