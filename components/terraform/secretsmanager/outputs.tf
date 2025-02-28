##################################################
# AWS Secrets Manager Component Outputs
##################################################

output "secret_arns" {
  description = "Map of secret names to their ARNs"
  value       = { for k, v in aws_secretsmanager_secret.this : k => v.arn }
}

output "secret_ids" {
  description = "Map of secret names to their secret IDs"
  value       = { for k, v in aws_secretsmanager_secret.this : k => v.id }
}

output "secret_names" {
  description = "Map of secret names to their full path names"
  value       = { for k, v in aws_secretsmanager_secret.this : k => v.name }
}

output "secret_versions" {
  description = "Map of secret names to their version IDs"
  value       = { for k, v in aws_secretsmanager_secret_version.this : k => v.version_id }
  sensitive   = true
}

output "secret_values" {
  description = "Map of secret names to their values - USE WITH CAUTION. DO NOT output these values to logs."
  value       = { for k, v in aws_secretsmanager_secret_version.this : k => v.secret_string }
  sensitive   = true
}

output "generated_passwords" {
  description = "Map of secret names to their generated random passwords (only for secrets with generate_random_password = true)"
  value       = { for k, v in random_password.this : k => v.result }
  sensitive   = true
}

output "secret_policies" {
  description = "Map of secret names to their attached policies"
  value       = { for k, v in aws_secretsmanager_secret_policy.this : k => v.policy }
}

output "rotation_enabled_secrets" {
  description = "Map of secret names with rotation enabled"
  value       = { for k, v in aws_secretsmanager_secret_rotation.this : k => {
    rotation_lambda_arn = v.rotation_lambda_arn
    automatically_after_days = v.rotation_rules[0].automatically_after_days
  }}
}