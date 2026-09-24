# Names as in cloudposse/terraform-aws-ec2-instance. The instance values come
# from whichever of aws_instance.default / aws_instance.from_launch_template
# exists; every value is null when enabled = false.

output "id" {
  description = "ID of the instance"
  value       = one(concat(aws_instance.default[*].id, aws_instance.from_launch_template[*].id))
}

output "arn" {
  description = "ARN of the instance"
  value       = one(concat(aws_instance.default[*].arn, aws_instance.from_launch_template[*].arn))
}

output "name" {
  description = "Instance name (its Name tag): <tags.Environment>-<name>"
  value       = local.enabled ? local.name_prefix : null
}

output "private_ip" {
  description = "Private IP of the instance"
  value       = one(concat(aws_instance.default[*].private_ip, aws_instance.from_launch_template[*].private_ip))
}

output "public_ip" {
  description = "Public IP of the instance, or null"
  value       = one(concat(aws_instance.default[*].public_ip, aws_instance.from_launch_template[*].public_ip))
}

output "private_dns" {
  description = "Private DNS name of the instance"
  value       = one(concat(aws_instance.default[*].private_dns, aws_instance.from_launch_template[*].private_dns))
}

# Cloud Posse outputs its ssh_key_pair input; this is the key the instance
# actually launched with (given or generated), which is what a consumer's
# ssh_key_pair needs.
output "ssh_key_pair" {
  description = "Name of the SSH key pair the instance launched with"
  value       = one(concat(aws_instance.default[*].key_name, aws_instance.from_launch_template[*].key_name))
}

output "security_group_id" {
  description = "ID of the instance's own security group (a string)"
  value       = one(aws_security_group.default[*].id)
}

output "security_group_ids" {
  description = "IDs of all security groups attached to the instance"
  value       = local.enabled ? local.security_group_ids : []
}

output "role" {
  description = "Name of the instance's IAM role"
  value       = one(aws_iam_role.default[*].name)
}

output "role_arn" {
  description = "ARN of the instance's IAM role"
  value       = one(aws_iam_role.default[*].arn)
}

output "instance_profile" {
  description = "Name of the instance profile"
  value       = one(aws_iam_instance_profile.default[*].name)
}

output "launch_template_id" {
  description = "ID of the launch template, if enable_launch_templates"
  value       = one(aws_launch_template.default[*].id)
}

output "ssh_key_secret_arn" {
  description = "ARN of the Secrets Manager secret holding the generated private key, if any"
  value       = one(aws_secretsmanager_secret.ssh_key[*].arn)
  sensitive   = true
}
