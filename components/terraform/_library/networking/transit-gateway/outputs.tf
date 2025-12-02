output "transit_gateway_id" {
  description = "ID of the Transit Gateway"
  value       = aws_ec2_transit_gateway.this.id
}

output "transit_gateway_arn" {
  description = "ARN of the Transit Gateway"
  value       = aws_ec2_transit_gateway.this.arn
}

output "transit_gateway_owner_id" {
  description = "Owner ID of the Transit Gateway"
  value       = aws_ec2_transit_gateway.this.owner_id
}

output "vpc_attachment_ids" {
  description = "Map of VPC attachment IDs"
  value       = { for k, v in aws_ec2_transit_gateway_vpc_attachment.this : k => v.id }
}

output "vpn_attachment_ids" {
  description = "Map of VPN attachment IDs"
  value       = { for k, v in aws_vpn_connection.this : k => v.transit_gateway_attachment_id }
}

output "customer_gateway_ids" {
  description = "Map of Customer Gateway IDs"
  value       = { for k, v in aws_customer_gateway.this : k => v.id }
}

output "vpn_connection_ids" {
  description = "Map of VPN Connection IDs"
  value       = { for k, v in aws_vpn_connection.this : k => v.id }
}

output "route_table_ids" {
  description = "Map of Transit Gateway route table IDs"
  value       = { for k, v in aws_ec2_transit_gateway_route_table.this : k => v.id }
}

output "peering_attachment_ids" {
  description = "Map of Transit Gateway peering attachment IDs"
  value       = { for k, v in aws_ec2_transit_gateway_peering_attachment.this : k => v.id }
}

output "ram_resource_share_arn" {
  description = "ARN of RAM resource share"
  value       = var.enable_ram_sharing ? aws_ram_resource_share.this[0].arn : null
}
