output "instance_ids" {
  value       = { for k, v in aws_instance.instances : k => v.id }
  description = "Map of instance names to instance IDs"
}

output "instance_arns" {
  value       = { for k, v in aws_instance.instances : k => v.arn }
  description = "Map of instance names to instance ARNs"
}

output "instance_public_ips" {
  value       = { for k, v in aws_instance.instances : k => v.public_ip }
  description = "Map of instance names to public IP addresses"
}

output "instance_private_ips" {
  value       = { for k, v in aws_instance.instances : k => v.private_ip }
  description = "Map of instance names to private IP addresses"
}

output "security_group_ids" {
  value       = { for k, v in aws_security_group.instances : k => v.id }
  description = "Map of instance names to security group IDs"
}

output "iam_role_arns" {
  value       = { for k, v in aws_iam_role.instances : k => v.arn }
  description = "Map of instance names to IAM role ARNs"
}

output "iam_role_names" {
  value       = { for k, v in aws_iam_role.instances : k => v.name }
  description = "Map of instance names to IAM role names"
}

output "iam_instance_profile_arns" {
  value       = { for k, v in aws_iam_instance_profile.instances : k => v.arn }
  description = "Map of instance names to IAM instance profile ARNs"
}

output "iam_instance_profile_names" {
  value       = { for k, v in aws_iam_instance_profile.instances : k => v.name }
  description = "Map of instance names to IAM instance profile names"
}
