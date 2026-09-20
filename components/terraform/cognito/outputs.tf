output "name_prefix" {
  description = "Resource name prefix this component builds its resource names from"
  value       = local.name_prefix
}

output "enabled" {
  description = "Whether this component is creating resources"
  value       = local.enabled
}

output "user_pool_id" {
  description = "Id of the user pool, null when the component is disabled"
  value       = one(aws_cognito_user_pool.this[*].id)
}

output "user_pool_arn" {
  description = "ARN of the user pool. apigateway takes this as cognito_user_pool_arns"
  value       = one(aws_cognito_user_pool.this[*].arn)
}

output "user_pool_endpoint" {
  description = "Endpoint of the user pool, used as the token issuer"
  value       = one(aws_cognito_user_pool.this[*].endpoint)
}

output "client_ids" {
  description = "App client ids keyed by the clients map key"
  value       = { for k, c in aws_cognito_user_pool_client.this : k => c.id }
}

output "hosted_ui_domain" {
  description = "Cognito hosted UI domain, null when no domain_prefix was set"
  value       = one(aws_cognito_user_pool_domain.this[*].domain)
}
