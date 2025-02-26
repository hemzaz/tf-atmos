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

output "security_group_vpc_id" {
  description = "VPC ID used for security groups"
  value = var.vpc_id
}