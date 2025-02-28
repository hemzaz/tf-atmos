output "rest_api_id" {
  description = "ID of the REST API"
  value       = local.create_rest_api ? aws_api_gateway_rest_api.rest_api[0].id : null
}

output "rest_api_arn" {
  description = "ARN of the REST API"
  value       = local.create_rest_api ? aws_api_gateway_rest_api.rest_api[0].arn : null
}

output "rest_api_execution_arn" {
  description = "Execution ARN of the REST API"
  value       = local.create_rest_api ? aws_api_gateway_rest_api.rest_api[0].execution_arn : null
}

output "rest_api_root_resource_id" {
  description = "Resource ID of the REST API's root resource"
  value       = local.create_rest_api ? aws_api_gateway_rest_api.rest_api[0].root_resource_id : null
}

output "rest_api_stage_name" {
  description = "Name of the REST API stage"
  value       = local.create_rest_api ? aws_api_gateway_stage.rest_stage[0].stage_name : null
}

output "rest_api_stage_arn" {
  description = "ARN of the REST API stage"
  value       = local.create_rest_api ? aws_api_gateway_stage.rest_stage[0].arn : null
}

output "rest_api_deployment_id" {
  description = "ID of the REST API deployment"
  value       = local.create_rest_api ? aws_api_gateway_deployment.rest_deployment[0].id : null
}

output "http_api_id" {
  description = "ID of the HTTP API"
  value       = local.create_http_api ? aws_apigatewayv2_api.http_api[0].id : null
}

output "http_api_arn" {
  description = "ARN of the HTTP API"
  value       = local.create_http_api ? aws_apigatewayv2_api.http_api[0].arn : null
}

output "http_api_execution_arn" {
  description = "Execution ARN of the HTTP API"
  value       = local.create_http_api ? aws_apigatewayv2_api.http_api[0].execution_arn : null
}

output "http_api_stage_id" {
  description = "ID of the HTTP API stage"
  value       = local.create_http_api ? aws_apigatewayv2_stage.http_stage[0].id : null
}

output "http_api_stage_arn" {
  description = "ARN of the HTTP API stage"
  value       = local.create_http_api ? aws_apigatewayv2_stage.http_stage[0].arn : null
}

output "rest_api_domain_name" {
  description = "Custom domain name for the REST API"
  value       = local.create_rest_api && local.domain_enabled ? aws_api_gateway_domain_name.rest_domain[0].domain_name : null
}

output "rest_api_domain_name_regional_domain_name" {
  description = "Regional domain name for the REST API custom domain"
  value       = local.create_rest_api && local.domain_enabled ? aws_api_gateway_domain_name.rest_domain[0].regional_domain_name : null
}

output "rest_api_domain_name_regional_zone_id" {
  description = "Regional hosted zone ID for the REST API custom domain"
  value       = local.create_rest_api && local.domain_enabled ? aws_api_gateway_domain_name.rest_domain[0].regional_zone_id : null
}

output "http_api_domain_name" {
  description = "Custom domain name for the HTTP API"
  value       = local.create_http_api && local.domain_enabled ? aws_apigatewayv2_domain_name.http_domain[0].domain_name : null
}

output "http_api_domain_name_target" {
  description = "Target domain name for the HTTP API custom domain"
  value       = local.create_http_api && local.domain_enabled ? aws_apigatewayv2_domain_name.http_domain[0].domain_name_configuration[0].target_domain_name : null
}

output "http_api_domain_name_hosted_zone_id" {
  description = "Hosted zone ID for the HTTP API custom domain"
  value       = local.create_http_api && local.domain_enabled ? aws_apigatewayv2_domain_name.http_domain[0].domain_name_configuration[0].hosted_zone_id : null
}

output "usage_plan_id" {
  description = "ID of the usage plan"
  value       = local.create_rest_api && var.create_usage_plan ? aws_api_gateway_usage_plan.usage_plan[0].id : null
}

output "usage_plan_arn" {
  description = "ARN of the usage plan"
  value       = local.create_rest_api && var.create_usage_plan ? aws_api_gateway_usage_plan.usage_plan[0].arn : null
}

output "api_key_id" {
  description = "ID of the API key"
  value       = local.create_rest_api && var.create_api_key ? aws_api_gateway_api_key.api_key[0].id : null
}

output "api_key_value" {
  description = "Value of the API key"
  value       = local.create_rest_api && var.create_api_key ? aws_api_gateway_api_key.api_key[0].value : null
  sensitive   = true
}

output "rest_api_authorizer_id" {
  description = "ID of the REST API authorizer"
  value = local.create_rest_api && var.authorizer_type == "COGNITO_USER_POOLS" ? aws_api_gateway_authorizer.rest_cognito[0].id : (
    local.create_rest_api && var.authorizer_type == "TOKEN" ? aws_api_gateway_authorizer.rest_lambda[0].id : null
  )
}

output "http_api_authorizer_id" {
  description = "ID of the HTTP API authorizer"
  value = local.create_http_api && var.authorizer_type == "JWT" ? aws_apigatewayv2_authorizer.http_jwt[0].id : (
    local.create_http_api && var.authorizer_type == "REQUEST" ? aws_apigatewayv2_authorizer.http_lambda[0].id : null
  )
}

output "log_group_name" {
  description = "Name of the CloudWatch log group for the API Gateway"
  value       = local.logs_enabled ? aws_cloudwatch_log_group.api_logs[0].name : null
}

output "log_group_arn" {
  description = "ARN of the CloudWatch log group for the API Gateway"
  value       = local.logs_enabled ? aws_cloudwatch_log_group.api_logs[0].arn : null
}

output "domain_name_route53_record" {
  description = "Route53 record for the custom domain name"
  value       = local.domain_enabled && var.zone_id != null ? aws_route53_record.api_domain[0].fqdn : null
}

output "dashboard_arn" {
  description = "ARN of the CloudWatch dashboard for the API Gateway"
  value       = var.create_dashboard ? aws_cloudwatch_dashboard.api_dashboard[0].dashboard_arn : null
}