# Lambda Pattern Library Module - Outputs
# Version: 1.0.0

output "function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.main.arn
}

output "function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.main.function_name
}

output "function_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.main.invoke_arn
}

output "function_qualified_arn" {
  description = "Qualified ARN of the Lambda function"
  value       = aws_lambda_function.main.qualified_arn
}

output "function_version" {
  description = "Latest published version of the Lambda function"
  value       = aws_lambda_function.main.version
}

output "alias_arn" {
  description = "ARN of the Lambda alias"
  value       = aws_lambda_alias.main.arn
}

output "alias_name" {
  description = "Name of the Lambda alias"
  value       = aws_lambda_alias.main.name
}

output "role_arn" {
  description = "ARN of the Lambda execution role"
  value       = var.create_role ? aws_iam_role.lambda[0].arn : var.role_arn
}

output "role_name" {
  description = "Name of the Lambda execution role"
  value       = one(aws_iam_role.lambda[*].name)
}

output "log_group_name" {
  description = "Name of the CloudWatch Log Group"
  value       = aws_cloudwatch_log_group.lambda.name
}

output "log_group_arn" {
  description = "ARN of the CloudWatch Log Group"
  value       = aws_cloudwatch_log_group.lambda.arn
}

output "function_url" {
  description = "URL of the Lambda function (if function URL is enabled)"
  value       = one(aws_lambda_function_url.main[*].function_url)
}

output "api_gateway_url" {
  description = "URL of the API Gateway (if API Gateway is enabled)"
  value       = local.create_rest_api ? aws_api_gateway_stage.main[0].invoke_url : one(aws_apigatewayv2_stage.main[*].invoke_url)
}

output "api_gateway_id" {
  description = "ID of the API Gateway (if enabled)"
  value       = local.create_rest_api ? aws_api_gateway_rest_api.main[0].id : one(aws_apigatewayv2_api.main[*].id)
}

output "dlq_arn" {
  description = "ARN of the Dead Letter Queue"
  value       = local.dlq_arn
}

output "sqs_queue_arn" {
  description = "ARN of the SQS queue (if created)"
  value       = one(aws_sqs_queue.trigger[*].arn)
}

output "sqs_queue_url" {
  description = "URL of the SQS queue (if created)"
  value       = one(aws_sqs_queue.trigger[*].url)
}

output "deployment_pattern" {
  description = "Deployment pattern used"
  value       = var.deployment_pattern
}
