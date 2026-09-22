output "security_group_ids" {
  description = "Map of security group names to their IDs"
  value = {
    for k, v in aws_security_group.this : k => v.id
  }
}

output "security_group_arns" {
  description = "Map of security group names to their ARNs"
  value = {
    for k, v in aws_security_group.this : k => v.arn
  }
}

output "security_group_names" {
  description = "Map of security group keys to the generated group names. The group itself is created from a name_prefix, so its full name is only known after apply; the readable form is also the Name tag."
  value = {
    for k, v in aws_security_group.this : k => v.name
  }
}

output "security_group_rule_ids" {
  description = "Map of normalized rule key (e.g. \"app/ingress[0]#cidr\") to the created rule's ID. The keys are the identities for_each uses, so this is what to read when a rule is unexpectedly replaced."
  value = {
    for k, v in aws_security_group_rule.this : k => v.id
  }
}

output "security_group_vpc_id" {
  description = "VPC ID used for security groups"
  value       = var.vpc_id
}
