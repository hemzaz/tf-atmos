resource "aws_vpn_gateway" "main" {
  count  = var.enable_vpn_gateway ? 1 : 0
  vpc_id = aws_vpc.main.id

  tags = merge(
    var.tags,
    {
      Name = "${var.tags["Environment"]}-vpn-gateway"
    }
  )
}

resource "aws_vpn_gateway_route_propagation" "private" {
  count          = var.enable_vpn_gateway ? length(var.private_subnets) : 0
  vpn_gateway_id = aws_vpn_gateway.main[0].id
  route_table_id = aws_route_table.private[count.index].id
}

resource "aws_vpn_gateway_route_propagation" "public" {
  count          = var.enable_vpn_gateway ? 1 : 0
  vpn_gateway_id = aws_vpn_gateway.main[0].id
  route_table_id = aws_route_table.public.id
}

# Add outputs for VPN Gateway
output "vpn_gateway_id" {
  value       = var.enable_vpn_gateway ? aws_vpn_gateway.main[0].id : null
  description = "The ID of the VPN Gateway"
}