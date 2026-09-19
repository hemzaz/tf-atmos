output "nat_gateway_ids" {
  description = "List of NAT Gateway IDs"
  value       = [for az in local.nat_gateway_azs : aws_nat_gateway.this[az].id]
}

output "nat_gateway_public_ips" {
  description = "List of NAT Gateway public IP addresses"
  value       = [for az in local.nat_gateway_azs : aws_eip.nat[az].public_ip]
}

output "nat_gateway_private_ips" {
  description = "List of NAT Gateway private IP addresses"
  value       = [for az in local.nat_gateway_azs : aws_nat_gateway.this[az].private_ip]
}

output "elastic_ip_ids" {
  description = "List of Elastic IP allocation IDs"
  value       = [for az in local.nat_gateway_azs : aws_eip.nat[az].id]
}

output "elastic_ip_allocation_ids" {
  description = "List of Elastic IP allocation IDs"
  value       = [for az in local.nat_gateway_azs : aws_eip.nat[az].allocation_id]
}

output "private_route_table_ids" {
  description = "List of private route table IDs"
  value       = [for az in keys(local.private_subnets) : aws_route_table.private[az].id]
}

output "nat_gateway_az_mapping" {
  description = "Map of availability zones to NAT Gateway IDs"
  value       = { for az, nat in aws_nat_gateway.this : az => nat.id }
}

output "cloudwatch_dashboard_arn" {
  description = "ARN of CloudWatch dashboard"
  value       = var.create_cloudwatch_dashboard ? aws_cloudwatch_dashboard.nat_gateway[0].dashboard_arn : null
}

output "estimated_monthly_cost_usd" {
  description = "Estimated monthly cost in USD (NAT Gateway hours + data processing)"
  value       = local.nat_gateway_count * ((0.045 * 730) + 45)
}
