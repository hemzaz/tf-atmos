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

# aws_subnet.database has existed all along with no way to read it, so every
# stack referencing .database_subnet_ids would have failed at plan time. Keyed
# off local.database_subnets because that is what the resource iterates.
output "database_subnet_ids" {
  value       = [for cidr in keys(local.database_subnets) : aws_subnet.database[cidr].id]
  description = "List of IDs of database subnets; empty when database_subnets is not set"
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

# Mirrors cloudposse-terraform-components/aws-vpc's interface_vpc_endpoints /
# gateway_vpc_endpoints / vpc_endpoint_interface_security_group_id outputs,
# shaped as id maps to match this component's collapsed var.vpc_endpoints
# list instead of Cloud Posse's two separate inputs.
output "vpc_endpoint_interface_ids" {
  value       = { for svc, ep in aws_vpc_endpoint.interface : svc => ep.id }
  description = "Map of AWS PrivateLink service name to Interface VPC endpoint ID; empty unless enable_vpc_endpoints is true"
}

output "vpc_endpoint_gateway_ids" {
  value       = { for svc, ep in aws_vpc_endpoint.gateway : svc => ep.id }
  description = "Map of AWS PrivateLink service name to Gateway VPC endpoint ID (s3, dynamodb); empty unless enable_vpc_endpoints is true"
}

output "vpc_endpoint_security_group_id" {
  value       = one(aws_security_group.vpc_endpoints[*].id)
  description = "ID of the shared security group attached to every Interface VPC endpoint; null unless enable_vpc_endpoints is true and at least one Interface endpoint is requested. Consumers can scope HTTPS egress to this group instead of the whole VPC CIDR."
}
