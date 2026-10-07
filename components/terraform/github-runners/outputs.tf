output "autoscaling_group_name" {
  description = "Name of the runners' Auto Scaling group; CI starts runners by executing its <name>-start policy"
  value       = one(aws_autoscaling_group.runner[*].name)
}

output "autoscaling_group_arn" {
  description = "ARN of the runners' Auto Scaling group"
  value       = one(aws_autoscaling_group.runner[*].arn)
}

output "security_group_id" {
  description = "The runners' security group: what a private endpoint admits (an eks instance's allowed_security_group_ids)"
  value       = one(aws_security_group.runner[*].id)
}

output "iam_role_arn" {
  description = "ARN of the runners' instance role"
  value       = one(aws_iam_role.runner[*].arn)
}

output "launch_template_id" {
  description = "ID of the runners' launch template"
  value       = one(aws_launch_template.runner[*].id)
}

output "runner_labels" {
  description = "Labels the runners register with (besides self-hosted, linux and x64)"
  value       = var.runner_labels
}

output "app_private_key_parameter_name" {
  description = "SSM SecureString the owner writes the GitHub App private key to, with app_key_kms_key_alias"
  value       = local.enabled ? local.app_key_parameter_name : null
}

output "app_key_kms_key_alias" {
  description = "Alias of the key the App private key parameter must be encrypted with (only the jit function may decrypt it)"
  value       = one(aws_kms_alias.app_key[*].name)
}

output "jit_function_name" {
  description = "Name of the jit function (its log group shows each launch's JIT configuration and each cleanup)"
  value       = one(aws_lambda_function.jit[*].function_name)
}

output "start_policy_name" {
  description = "The +1 scaling policy CI executes to start one runner (<autoscaling_group_name>-start)"
  value       = one(aws_autoscaling_policy.start[*].name)
}
