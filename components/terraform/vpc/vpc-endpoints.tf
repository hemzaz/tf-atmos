# VPC Endpoints (AWS PrivateLink). Mirrors
# cloudposse-terraform-components/aws-vpc's interface_vpc_endpoints /
# vpc_gateway_endpoints inputs, collapsed here into the single
# var.vpc_endpoints list: "s3" and "dynamodb" are the only AWS services that
# use the Gateway endpoint type (free, route-table based); every other name
# in the list gets an Interface endpoint (ENI + private DNS in the private
# subnets, hourly + per-GB charge).
#
# Why this matters for NACLs: an Interface endpoint's ENI sits inside the
# private subnets with an address in the VPC CIDR. A VPC-attached Lambda's
# call to it, and the endpoint's reply, both stay within the VPC CIDR, so
# both legs are already covered by the "allow VPC CIDR" NACL rules (private
# ingress rule 100, egress rule 130 in network-acls.tf) with no /0 ingress
# widening needed -- unlike the same call going out via the NAT gateway,
# whose reply arrives from a public IP and would need an inbound /0 NACL
# rule sized to the Hyperplane ENI's full ephemeral port range. See
# stacks/catalog/templates/microservices-platform.yaml's
# microservices/lambda/redis-auth-rotation for the consumer this exists for.

locals {
  vpc_endpoint_gateway_services   = toset([for s in var.vpc_endpoints : s if contains(["s3", "dynamodb"], s)])
  vpc_endpoint_interface_services = toset([for s in var.vpc_endpoints : s if !contains(["s3", "dynamodb"], s)])
}

# Shared by every Interface endpoint. Scoped to HTTPS from the VPC CIDR only
# -- never 0.0.0.0/0 -- since every caller is inside this VPC.
resource "aws_security_group" "vpc_endpoints" {
  count       = var.enable_vpc_endpoints && length(local.vpc_endpoint_interface_services) > 0 ? 1 : 0
  name        = "${var.tags["Environment"]}-vpce-sg"
  description = "Allow HTTPS from the VPC CIDR to interface VPC endpoints"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from the VPC CIDR"
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    cidr_blocks = [var.ipv4_primary_cidr_block]
  }

  egress {
    description = "Allow all outbound"
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.tags["Environment"]}-vpce-sg" }
}

resource "aws_vpc_endpoint" "gateway" {
  for_each          = var.enable_vpc_endpoints ? local.vpc_endpoint_gateway_services : toset([])
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.region}.${each.value}"
  vpc_endpoint_type = "Gateway"

  # Every route table this VPC manages: gateway endpoints add a prefix-list
  # route to each one directly, no ENI involved.
  route_table_ids = concat(
    [aws_route_table.public.id],
    [for rt in aws_route_table.private : rt.id],
  )

  tags = { Name = "${var.tags["Environment"]}-vpce-${each.value}" }
}

resource "aws_vpc_endpoint" "interface" {
  for_each            = var.enable_vpc_endpoints ? local.vpc_endpoint_interface_services : toset([])
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [for cidr in var.private_subnets : aws_subnet.private[cidr].id]
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true

  tags = { Name = "${var.tags["Environment"]}-vpce-${each.value}" }
}
