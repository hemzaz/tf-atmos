output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.this.id
}

output "vpc_arn" {
  description = "ARN of the VPC"
  value       = aws_vpc.this.arn
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.this.cidr_block
}

output "vpc_ipv6_cidr_block" {
  description = "IPv6 CIDR block of the VPC"
  value       = var.enable_ipv6 ? aws_vpc.this.ipv6_cidr_block : null
}

output "vpc_main_route_table_id" {
  description = "ID of the main route table associated with the VPC"
  value       = aws_vpc.this.main_route_table_id
}

output "vpc_default_network_acl_id" {
  description = "ID of the default network ACL"
  value       = aws_vpc.this.default_network_acl_id
}

output "vpc_default_security_group_id" {
  description = "ID of the default security group"
  value       = aws_vpc.this.default_security_group_id
}

#------------------------------------------------------------------------------
# Public Subnets
#------------------------------------------------------------------------------
output "public_subnet_ids" {
  description = "List of IDs of public subnets"
  value       = aws_subnet.public[*].id
}

output "public_subnet_arns" {
  description = "List of ARNs of public subnets"
  value       = aws_subnet.public[*].arn
}

output "public_subnet_cidrs" {
  description = "List of CIDR blocks of public subnets"
  value       = aws_subnet.public[*].cidr_block
}

output "public_subnet_azs" {
  description = "List of availability zones of public subnets"
  value       = aws_subnet.public[*].availability_zone
}

output "public_route_table_ids" {
  description = "List of IDs of public route tables"
  value       = aws_route_table.public[*].id
}

#------------------------------------------------------------------------------
# Private Subnets
#------------------------------------------------------------------------------
output "private_subnet_ids" {
  description = "List of IDs of private subnets"
  value       = aws_subnet.private[*].id
}

output "private_subnet_arns" {
  description = "List of ARNs of private subnets"
  value       = aws_subnet.private[*].arn
}

output "private_subnet_cidrs" {
  description = "List of CIDR blocks of private subnets"
  value       = aws_subnet.private[*].cidr_block
}

output "private_subnet_azs" {
  description = "List of availability zones of private subnets"
  value       = aws_subnet.private[*].availability_zone
}

output "private_route_table_ids" {
  description = "List of IDs of private route tables"
  value       = aws_route_table.private[*].id
}

#------------------------------------------------------------------------------
# Database Subnets
#------------------------------------------------------------------------------
output "database_subnet_ids" {
  description = "List of IDs of database subnets"
  value       = aws_subnet.database[*].id
}

output "database_subnet_arns" {
  description = "List of ARNs of database subnets"
  value       = aws_subnet.database[*].arn
}

output "database_subnet_cidrs" {
  description = "List of CIDR blocks of database subnets"
  value       = aws_subnet.database[*].cidr_block
}

output "database_subnet_azs" {
  description = "List of availability zones of database subnets"
  value       = aws_subnet.database[*].availability_zone
}

output "database_subnet_group_id" {
  description = "ID of the database subnet group"
  value       = try(aws_db_subnet_group.this[0].id, null)
}

output "database_subnet_group_name" {
  description = "Name of the database subnet group"
  value       = try(aws_db_subnet_group.this[0].name, null)
}

output "database_route_table_ids" {
  description = "List of IDs of database route tables"
  value       = aws_route_table.database[*].id
}

#------------------------------------------------------------------------------
# Internet Gateway
#------------------------------------------------------------------------------
output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = try(aws_internet_gateway.this[0].id, null)
}

output "internet_gateway_arn" {
  description = "ARN of the Internet Gateway"
  value       = try(aws_internet_gateway.this[0].arn, null)
}

#------------------------------------------------------------------------------
# NAT Gateways
#------------------------------------------------------------------------------
output "nat_gateway_ids" {
  description = "List of NAT Gateway IDs"
  value       = aws_nat_gateway.this[*].id
}

output "nat_gateway_public_ips" {
  description = "List of public Elastic IPs associated with NAT Gateways"
  value       = aws_eip.nat[*].public_ip
}

output "nat_gateway_private_ips" {
  description = "List of private IPs associated with NAT Gateways"
  value       = aws_nat_gateway.this[*].private_ip
}

output "nat_gateway_network_interface_ids" {
  description = "List of network interface IDs assigned to NAT Gateways"
  value       = aws_nat_gateway.this[*].network_interface_id
}

#------------------------------------------------------------------------------
# VPN Gateway
#------------------------------------------------------------------------------
output "vpn_gateway_id" {
  description = "ID of the VPN Gateway"
  value       = try(aws_vpn_gateway.this[0].id, null)
}

output "vpn_gateway_arn" {
  description = "ARN of the VPN Gateway"
  value       = try(aws_vpn_gateway.this[0].arn, null)
}

#------------------------------------------------------------------------------
# Transit Gateway
#------------------------------------------------------------------------------
output "transit_gateway_attachment_id" {
  description = "ID of the Transit Gateway VPC attachment"
  value       = try(aws_ec2_transit_gateway_vpc_attachment.this[0].id, null)
}

#------------------------------------------------------------------------------
# VPC Endpoints
#------------------------------------------------------------------------------
output "vpc_endpoint_ids" {
  description = "Map of VPC endpoint IDs"
  value = {
    for k, v in aws_vpc_endpoint.this : k => v.id
  }
}

output "vpc_endpoint_arns" {
  description = "Map of VPC endpoint ARNs"
  value = {
    for k, v in aws_vpc_endpoint.this : k => v.arn
  }
}

output "vpc_endpoint_dns_entries" {
  description = "Map of VPC endpoint DNS entries"
  value = {
    for k, v in aws_vpc_endpoint.this : k => v.dns_entry
  }
}

output "vpc_endpoint_network_interface_ids" {
  description = "Map of VPC endpoint network interface IDs (Interface endpoints only)"
  value = {
    for k, v in aws_vpc_endpoint.this : k => v.network_interface_ids if v.vpc_endpoint_type == "Interface"
  }
}

#------------------------------------------------------------------------------
# Flow Logs
#------------------------------------------------------------------------------
output "flow_logs_id" {
  description = "ID of the VPC Flow Logs"
  value       = try(aws_flow_log.this[0].id, null)
}

output "flow_logs_log_group_name" {
  description = "Name of the CloudWatch log group for flow logs"
  value       = try(aws_cloudwatch_log_group.flow_logs[0].name, null)
}

output "flow_logs_log_group_arn" {
  description = "ARN of the CloudWatch log group for flow logs"
  value       = try(aws_cloudwatch_log_group.flow_logs[0].arn, null)
}

output "flow_logs_iam_role_arn" {
  description = "ARN of the IAM role for VPC flow logs"
  value       = try(aws_iam_role.flow_logs[0].arn, null)
}

#------------------------------------------------------------------------------
# DHCP Options
#------------------------------------------------------------------------------
output "dhcp_options_id" {
  description = "ID of the DHCP options set"
  value       = try(aws_vpc_dhcp_options.this[0].id, null)
}

#------------------------------------------------------------------------------
# Summary Outputs
#------------------------------------------------------------------------------
output "availability_zones" {
  description = "List of availability zones used"
  value       = var.availability_zones
}

output "nat_gateway_count" {
  description = "Number of NAT Gateways created"
  value       = local.nat_gateway_count
}

output "subnet_counts" {
  description = "Number of subnets created by tier"
  value = {
    public   = length(var.public_subnets)
    private  = length(var.private_subnets)
    database = length(var.database_subnets)
  }
}
