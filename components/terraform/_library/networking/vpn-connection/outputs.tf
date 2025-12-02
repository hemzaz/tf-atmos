output "vpn_connection_id" {
  description = "ID of the VPN connection"
  value       = aws_vpn_connection.this.id
}

output "vpn_connection_transit_gateway_attachment_id" {
  description = "Transit Gateway attachment ID"
  value       = var.use_transit_gateway ? aws_vpn_connection.this.transit_gateway_attachment_id : null
}

output "customer_gateway_id" {
  description = "ID of the customer gateway"
  value       = aws_customer_gateway.this.id
}

output "vpn_gateway_id" {
  description = "ID of the virtual private gateway"
  value       = var.use_transit_gateway ? null : aws_vpn_gateway.this[0].id
}

output "tunnel1_address" {
  description = "Public IP address of tunnel 1"
  value       = aws_vpn_connection.this.tunnel1_address
}

output "tunnel2_address" {
  description = "Public IP address of tunnel 2"
  value       = aws_vpn_connection.this.tunnel2_address
}

output "tunnel1_preshared_key" {
  description = "Pre-shared key for tunnel 1"
  value       = aws_vpn_connection.this.tunnel1_preshared_key
  sensitive   = true
}

output "tunnel2_preshared_key" {
  description = "Pre-shared key for tunnel 2"
  value       = aws_vpn_connection.this.tunnel2_preshared_key
  sensitive   = true
}

output "tunnel1_cgw_inside_address" {
  description = "Customer gateway inside IP for tunnel 1"
  value       = aws_vpn_connection.this.tunnel1_cgw_inside_address
}

output "tunnel2_cgw_inside_address" {
  description = "Customer gateway inside IP for tunnel 2"
  value       = aws_vpn_connection.this.tunnel2_cgw_inside_address
}

output "tunnel1_vgw_inside_address" {
  description = "VGW inside IP for tunnel 1"
  value       = aws_vpn_connection.this.tunnel1_vgw_inside_address
}

output "tunnel2_vgw_inside_address" {
  description = "VGW inside IP for tunnel 2"
  value       = aws_vpn_connection.this.tunnel2_vgw_inside_address
}

output "tunnel1_bgp_asn" {
  description = "BGP ASN for tunnel 1"
  value       = aws_vpn_connection.this.tunnel1_bgp_asn
}

output "tunnel2_bgp_asn" {
  description = "BGP ASN for tunnel 2"
  value       = aws_vpn_connection.this.tunnel2_bgp_asn
}

output "cloudwatch_log_group_tunnel1_arn" {
  description = "ARN of CloudWatch log group for tunnel 1"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.tunnel1[0].arn : null
}

output "cloudwatch_log_group_tunnel2_arn" {
  description = "ARN of CloudWatch log group for tunnel 2"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.tunnel2[0].arn : null
}
