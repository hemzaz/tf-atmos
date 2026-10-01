output "role_arn" {
  description = "ARN of the API Gateway CloudWatch Logs role set on the account (null when enabled is false)"
  value       = var.enabled ? aws_iam_role.this[0].arn : null
}

output "role_name" {
  description = "Name of the API Gateway CloudWatch Logs role (null when enabled is false)"
  value       = var.enabled ? aws_iam_role.this[0].name : null
}
