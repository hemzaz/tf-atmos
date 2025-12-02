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
  value       = var.create_role ? aws_iam_role.lambda[0].name : null
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
  value       = var.enable_function_url ? aws_lambda_function_url.main[0].function_url : null
}

output "api_gateway_url" {
  description = "URL of the API Gateway (if API Gateway is enabled)"
  value       = var.enable_api_gateway ? module.api_gateway[0].api_url : null
}

output "api_gateway_id" {
  description = "ID of the API Gateway (if enabled)"
  value       = var.enable_api_gateway ? module.api_gateway[0].api_id : null
}

output "dlq_arn" {
  description = "ARN of the Dead Letter Queue"
  value       = var.enable_dlq ? (var.dlq_target_arn != null ? var.dlq_target_arn : aws_sqs_queue.dlq[0].arn) : null
}

output "sqs_queue_arn" {
  description = "ARN of the SQS queue (if created)"
  value       = var.create_sqs_queue ? aws_sqs_queue.trigger[0].arn : null
}

output "sqs_queue_url" {
  description = "URL of the SQS queue (if created)"
  value       = var.create_sqs_queue ? aws_sqs_queue.trigger[0].url : null
}

output "deployment_pattern" {
  description = "Deployment pattern used"
  value       = var.deployment_pattern
}
