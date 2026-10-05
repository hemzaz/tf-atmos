output "token_parameter_name" {
  description = "SSM SecureString holding the current runner registration token (github-runners' registration_token_parameter_name)"
  value       = one(aws_ssm_parameter.token[*].name)
}

output "token_parameter_arn" {
  description = "ARN of the token parameter"
  value       = one(aws_ssm_parameter.token[*].arn)
}

output "function_name" {
  description = "Name of the rotator function; invoke it once after the first apply so the token exists before the schedule's first run"
  value       = one(aws_lambda_function.function[*].function_name)
}

output "function_arn" {
  description = "ARN of the rotator function"
  value       = one(aws_lambda_function.function[*].arn)
}

output "role_arn" {
  description = "ARN of the rotator function's execution role"
  value       = one(aws_iam_role.function[*].arn)
}

output "github_scope" {
  description = "The scope the runners register to: owner/repository or the organization"
  value       = local.scope
}
