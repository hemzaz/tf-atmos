output "autoscaling_group_name" {
  description = "Name of the runners' Auto Scaling group; CI raises its desired capacity to start runners"
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
  description = "Labels the runners register with (besides self-hosted, linux, x64 and the instance type)"
  value       = var.runner_labels
}
