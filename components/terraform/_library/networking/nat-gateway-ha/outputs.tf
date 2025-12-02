output "nat_gateway_ids" {
  description = "List of NAT Gateway IDs"
  value       = aws_nat_gateway.this[*].id
}

output "nat_gateway_public_ips" {
  description = "List of NAT Gateway public IP addresses"
  value       = aws_eip.nat[*].public_ip
}

output "nat_gateway_private_ips" {
  description = "List of NAT Gateway private IP addresses"
  value       = aws_nat_gateway.this[*].private_ip
}

output "elastic_ip_ids" {
  description = "List of Elastic IP allocation IDs"
  value       = aws_eip.nat[*].id
}

output "elastic_ip_allocation_ids" {
  description = "List of Elastic IP allocation IDs"
  value       = aws_eip.nat[*].allocation_id
}

output "private_route_table_ids" {
  description = "List of private route table IDs"
  value       = aws_route_table.private[*].id
}

output "nat_gateway_az_mapping" {
  description = "Map of availability zones to NAT Gateway IDs"
  value = {
    for i, az in var.availability_zones :
    az => aws_nat_gateway.this[i].id
  }
}

output "cloudwatch_dashboard_arn" {
  description = "ARN of CloudWatch dashboard"
  value       = var.create_cloudwatch_dashboard ? aws_cloudwatch_dashboard.nat_gateway[0].dashboard_arn : null
}

output "estimated_monthly_cost_usd" {
  description = "Estimated monthly cost in USD (NAT Gateway hours + data processing)"
  value       = local.nat_gateway_count * ((0.045 * 730) + 45)
}
