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

output "generated_key_names" {
  value = merge(
    { for k, v in aws_key_pair.generated : k => v.key_name },
    local.create_global_key ? { "global" = aws_key_pair.global[0].key_name } : {}
  )
  description = "Map of instance names to generated SSH key names, includes global key if created"
}

output "ssh_key_secret_arns" {
  value = merge(
    { for k, v in aws_secretsmanager_secret.ssh_key : k => v.arn },
    local.create_global_key && var.store_ssh_keys_in_secrets_manager ? { "global" = aws_secretsmanager_secret.global_ssh_key[0].arn } : {}
  )
  description = "Map of instance names to Secret Manager ARNs containing SSH keys"
  sensitive   = true
}

output "global_key_name" {
  value       = local.create_global_key ? aws_key_pair.global[0].key_name : null
  description = "Name of the generated global SSH key, if created"
}

output "global_key_secret_arn" {
  value       = local.create_global_key && var.store_ssh_keys_in_secrets_manager ? aws_secretsmanager_secret.global_ssh_key[0].arn : null
  description = "ARN of the Secret Manager secret containing the global SSH key, if created"
  sensitive   = true
}

output "instances_using_global_key" {
  value       = local.create_global_key ? keys(local.instances_using_global_key) : []
  description = "List of instance names using the global SSH key"
}

output "instances_using_individual_keys" {
  value       = keys(local.instances_requiring_keys)
  description = "List of instance names using individually generated SSH keys"
}

# Scalar outputs for the component's single EC2 instance, named as in Cloud Posse's
# ec2-instance and ec2-bastion-server modules, so another instance reads
# `!terraform.state ec2/bastion .ssh_key_pair` without knowing the instance's map key.
#
# one() never picks among several instances: with no enabled instance these are null,
# and with more than one the plan fails ("must be a list, set, or tuple value with
# either zero or one elements"). A multi-instance component must read the map outputs.

output "ssh_key_pair" {
  # The key the instance launched with, whichever way main.tf resolved it: its own
  # key_name, its generated key, the global key, or default_key_name. Not
  # global_key_name, which an instance with its own key_name does not use.
  value       = one([for i in aws_instance.instances : i.key_name])
  description = "Name of the SSH key pair on the component's only EC2 instance (null without an instance or key; the plan fails with more than one instance)"
}

output "security_group_id" {
  value       = one([for sg in aws_security_group.instances : sg.id])
  description = "ID of the security group created for the component's only EC2 instance (null without an instance; the plan fails with more than one)"
}
