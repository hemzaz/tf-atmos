output "function_arn" {
  value       = aws_lambda_function.main.arn
  description = "ARN of the Lambda function"
}

output "function_name" {
  value       = aws_lambda_function.main.function_name
  description = "Name of the Lambda function"
}

output "function_invoke_arn" {
  value       = aws_lambda_function.main.invoke_arn
  description = "Invoke ARN of the Lambda function"
}

output "function_version" {
  value       = aws_lambda_function.main.version
  description = "Latest published version of the Lambda function"
}

output "role_arn" {
  value       = aws_iam_role.lambda.arn
  description = "ARN of the IAM role for the Lambda function"
}

output "role_name" {
  value       = aws_iam_role.lambda.name
  description = "Name of the IAM role for the Lambda function"
}

output "log_group_name" {
  value       = aws_cloudwatch_log_group.lambda.name
  description = "Name of the CloudWatch log group for the Lambda function"
}

output "log_group_arn" {
  value       = aws_cloudwatch_log_group.lambda.arn
  description = "ARN of the CloudWatch log group for the Lambda function"
}

output "security_group_id" {
  value       = length(var.subnet_ids) > 0 ? aws_security_group.lambda[0].id : null
  description = "ID of the security group for the Lambda function"
}

output "alias_arn" {
  value       = var.create_alias ? aws_lambda_alias.main[0].arn : null
  description = "ARN of the Lambda function alias"
}

output "event_source_mapping_uuids" {
  value       = { for k, v in aws_lambda_event_source_mapping.this : k => v.uuid }
  description = "UUIDs of the event source mappings, keyed by event_source_mappings key"
}

output "event_source_mapping_arns" {
  value       = { for k, v in aws_lambda_event_source_mapping.this : k => v.arn }
  description = "ARNs of the event source mappings, keyed by event_source_mappings key"
}

output "alias_invoke_arn" {
  value       = var.create_alias ? aws_lambda_alias.main[0].invoke_arn : null
  description = "Invoke ARN of the Lambda function alias"
}