output "gateway_endpoint_ids" {
  description = "Map of Gateway endpoint IDs"
  value       = { for k, v in aws_vpc_endpoint.gateway : k => v.id }
}

output "gateway_endpoint_arns" {
  description = "Map of Gateway endpoint ARNs"
  value       = { for k, v in aws_vpc_endpoint.gateway : k => v.arn }
}

output "interface_endpoint_ids" {
  description = "Map of Interface endpoint IDs"
  value       = { for k, v in aws_vpc_endpoint.interface : k => v.id }
}

output "interface_endpoint_arns" {
  description = "Map of Interface endpoint ARNs"
  value       = { for k, v in aws_vpc_endpoint.interface : k => v.arn }
}

output "interface_endpoint_dns_entries" {
  description = "Map of Interface endpoint DNS entries"
  value = {
    for k, v in aws_vpc_endpoint.interface : k => v.dns_entry
  }
}

output "interface_endpoint_network_interface_ids" {
  description = "Map of Interface endpoint network interface IDs"
  value = {
    for k, v in aws_vpc_endpoint.interface : k => v.network_interface_ids
  }
}

output "security_group_id" {
  description = "Security group ID for interface endpoints"
  value       = length(aws_security_group.interface_endpoints) > 0 ? aws_security_group.interface_endpoints[0].id : null
}

output "endpoint_services" {
  description = "Map of endpoint service names"
  value       = local.service_names
}

output "estimated_monthly_cost_usd" {
  description = "Estimated monthly cost in USD (Interface endpoints only)"
  value = {
    interface_endpoints = local.interface_endpoint_monthly_cost
    data_processing     = "Variable: $0.01/GB"
    gateway_endpoints   = 0
    total_fixed         = local.estimated_monthly_cost
  }
}

output "cost_breakdown" {
  description = "Detailed cost breakdown"
  value = {
    interface_endpoint_count = local.interface_endpoint_count
    avg_azs_per_endpoint     = local.avg_azs_per_endpoint
    hourly_cost_per_az       = 0.01
    monthly_hours            = 730
    estimated_monthly_total  = local.estimated_monthly_cost
    note                     = "Does not include variable data processing charges ($0.01/GB)"
  }
}
