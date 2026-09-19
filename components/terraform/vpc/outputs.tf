output "vpc_id" {
  value       = aws_vpc.main.id
  description = "The ID of the VPC"
}

output "vpc_cidr" {
  value       = aws_vpc.main.cidr_block
  description = "The CIDR block of the VPC"
}

output "private_subnet_ids" {
  value       = [for cidr in var.private_subnets : aws_subnet.private[cidr].id]
  description = "List of IDs of private subnets"
}

output "public_subnet_ids" {
  value       = [for cidr in var.public_subnets : aws_subnet.public[cidr].id]
  description = "List of IDs of public subnets"
}

output "private_route_table_ids" {
  value       = [for cidr in var.private_subnets : aws_route_table.private[cidr].id]
  description = "List of IDs of private route tables"
}

output "public_route_table_id" {
  value       = aws_route_table.public.id
  description = "ID of the public route table"
}

output "default_security_group_id" {
  value       = aws_security_group.default.id
  description = "The ID of this component's shared default security group (aws_security_group.default), not the VPC's AWS-created default group"
}

output "nat_gateway_ids" {
  value       = [for i in local.nat_gateway_subnet_indices : aws_nat_gateway.main[var.public_subnets[i]].id]
  description = "List of NAT Gateway IDs"
}

output "vpc_management_role_arn" {
  value       = var.create_vpc_iam_role ? aws_iam_role.vpc_management_role[0].arn : ""
  description = "ARN of the VPC management IAM role"
}

output "vpc_management_instance_profile_arn" {
  value       = var.create_vpc_iam_role ? aws_iam_instance_profile.vpc_management_profile[0].arn : ""
  description = "ARN of the VPC management instance profile"
}