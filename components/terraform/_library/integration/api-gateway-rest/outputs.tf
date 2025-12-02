##############################################
# REST API Outputs
##############################################

output "rest_api_id" {
  description = "ID of the REST API"
  value       = aws_api_gateway_rest_api.main.id
}

output "rest_api_arn" {
  description = "ARN of the REST API"
  value       = aws_api_gateway_rest_api.main.arn
}

output "rest_api_name" {
  description = "Name of the REST API"
  value       = aws_api_gateway_rest_api.main.name
}

output "root_resource_id" {
  description = "Root resource ID of the REST API"
  value       = aws_api_gateway_rest_api.main.root_resource_id
}

output "execution_arn" {
  description = "Execution ARN for Lambda permissions"
  value       = aws_api_gateway_rest_api.main.execution_arn
}

##############################################
# Stage Outputs
##############################################

output "stage_id" {
  description = "ID of the stage"
  value       = aws_api_gateway_stage.main.id
}

output "stage_arn" {
  description = "ARN of the stage"
  value       = aws_api_gateway_stage.main.arn
}

output "stage_name" {
  description = "Name of the stage"
  value       = aws_api_gateway_stage.main.stage_name
}

output "stage_invoke_url" {
  description = "Invoke URL for the stage"
  value       = aws_api_gateway_stage.main.invoke_url
}

##############################################
# Deployment Outputs
##############################################

output "deployment_id" {
  description = "ID of the deployment"
  value       = aws_api_gateway_deployment.main.id
}

##############################################
# API Key Outputs
##############################################

output "api_key_ids" {
  description = "Map of API key names to IDs"
  value       = { for k, v in aws_api_gateway_api_key.main : k => v.id }
}

output "api_key_values" {
  description = "Map of API key names to values"
  value       = { for k, v in aws_api_gateway_api_key.main : k => v.value }
  sensitive   = true
}

##############################################
# Usage Plan Outputs
##############################################

output "usage_plan_ids" {
  description = "Map of usage plan names to IDs"
  value       = { for k, v in aws_api_gateway_usage_plan.main : k => v.id }
}

##############################################
# Custom Domain Outputs
##############################################

output "custom_domain_name" {
  description = "Custom domain name"
  value       = var.custom_domain_name != null ? aws_api_gateway_domain_name.main[0].domain_name : null
}

output "custom_domain_regional_domain_name" {
  description = "Regional domain name for custom domain"
  value       = var.custom_domain_name != null && var.endpoint_type == "REGIONAL" ? aws_api_gateway_domain_name.main[0].regional_domain_name : null
}

output "custom_domain_regional_zone_id" {
  description = "Regional Route53 zone ID for custom domain"
  value       = var.custom_domain_name != null && var.endpoint_type == "REGIONAL" ? aws_api_gateway_domain_name.main[0].regional_zone_id : null
}

output "custom_domain_cloudfront_domain_name" {
  description = "CloudFront domain name for custom domain (EDGE)"
  value       = var.custom_domain_name != null && var.endpoint_type == "EDGE" ? aws_api_gateway_domain_name.main[0].cloudfront_domain_name : null
}

output "custom_domain_cloudfront_zone_id" {
  description = "CloudFront Route53 zone ID for custom domain (EDGE)"
  value       = var.custom_domain_name != null && var.endpoint_type == "EDGE" ? aws_api_gateway_domain_name.main[0].cloudfront_zone_id : null
}

##############################################
# Request Validator Outputs
##############################################

output "request_validator_ids" {
  description = "Map of request validator names to IDs"
  value       = { for k, v in aws_api_gateway_request_validator.main : k => v.id }
}

##############################################
# CloudWatch Logs Outputs
##############################################

output "log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = var.enable_access_logging ? aws_cloudwatch_log_group.api[0].name : null
}

output "log_group_arn" {
  description = "ARN of the CloudWatch log group"
  value       = var.enable_access_logging ? aws_cloudwatch_log_group.api[0].arn : null
}

##############################################
# CloudWatch Alarm Outputs
##############################################

output "alarm_error_rate_arn" {
  description = "ARN of the error rate alarm"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.error_rate[0].arn : null
}

output "alarm_latency_arn" {
  description = "ARN of the latency alarm"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.latency[0].arn : null
}
