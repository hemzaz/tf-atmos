locals {
  name_prefix = var.name_prefix

  common_tags = merge(
    {
      Name        = local.name_prefix
      Environment = var.environment
      ManagedBy   = "Terraform"
      Module      = "transit-gateway"
    },
    var.tags
  )
}

#------------------------------------------------------------------------------
# Transit Gateway
#------------------------------------------------------------------------------
resource "aws_ec2_transit_gateway" "this" {
  description                     = var.description
  amazon_side_asn                 = var.amazon_side_asn
  auto_accept_shared_attachments  = var.auto_accept_shared_attachments ? "enable" : "disable"
  default_route_table_association = var.default_route_table_association ? "enable" : "disable"
  default_route_table_propagation = var.default_route_table_propagation ? "enable" : "disable"
  dns_support                     = var.dns_support ? "enable" : "disable"
  vpn_ecmp_support                = var.vpn_ecmp_support ? "enable" : "disable"
  multicast_support               = var.multicast_support ? "enable" : "disable"

  transit_gateway_cidr_blocks = var.transit_gateway_cidr_blocks

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-tgw"
    }
  )
}

#------------------------------------------------------------------------------
# VPC Attachments
#------------------------------------------------------------------------------
resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  for_each = var.vpc_attachments

  transit_gateway_id = aws_ec2_transit_gateway.this.id
  vpc_id             = each.value.vpc_id
  subnet_ids         = each.value.subnet_ids

  dns_support                                     = lookup(each.value, "dns_support", true) ? "enable" : "disable"
  ipv6_support                                    = lookup(each.value, "ipv6_support", false) ? "enable" : "disable"
  appliance_mode_support                          = lookup(each.value, "appliance_mode_support", false) ? "enable" : "disable"
  transit_gateway_default_route_table_association = lookup(each.value, "default_route_table_association", var.default_route_table_association)
  transit_gateway_default_route_table_propagation = lookup(each.value, "default_route_table_propagation", var.default_route_table_propagation)

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-tgw-attachment-${each.key}"
    },
    lookup(each.value, "tags", {})
  )
}

#------------------------------------------------------------------------------
# VPN Attachments
#------------------------------------------------------------------------------
resource "aws_customer_gateway" "this" {
  for_each = var.vpn_attachments

  bgp_asn    = each.value.bgp_asn
  ip_address = each.value.ip_address
  type       = "ipsec.1"

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-cgw-${each.key}"
    }
  )
}

resource "aws_vpn_connection" "this" {
  for_each = var.vpn_attachments

  customer_gateway_id = aws_customer_gateway.this[each.key].id
  transit_gateway_id  = aws_ec2_transit_gateway.this.id
  type                = "ipsec.1"

  static_routes_only = lookup(each.value, "static_routes_only", false)

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-vpn-${each.key}"
    }
  )
}

#------------------------------------------------------------------------------
# Transit Gateway Route Tables
#------------------------------------------------------------------------------
resource "aws_ec2_transit_gateway_route_table" "this" {
  for_each = var.transit_gateway_route_tables

  transit_gateway_id = aws_ec2_transit_gateway.this.id

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-tgw-rt-${each.key}"
    }
  )
}

#------------------------------------------------------------------------------
# Route Table Associations
#------------------------------------------------------------------------------
resource "aws_ec2_transit_gateway_route_table_association" "vpc" {
  for_each = {
    for k, v in var.vpc_attachments : k => v
    if lookup(v, "route_table_id", null) != null
  }

  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this[each.key].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.this[each.value.route_table_id].id
}

resource "aws_ec2_transit_gateway_route_table_association" "vpn" {
  for_each = {
    for k, v in var.vpn_attachments : k => v
    if lookup(v, "route_table_id", null) != null
  }

  transit_gateway_attachment_id  = aws_vpn_connection.this[each.key].transit_gateway_attachment_id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.this[each.value.route_table_id].id
}

#------------------------------------------------------------------------------
# Route Table Propagations
#------------------------------------------------------------------------------
resource "aws_ec2_transit_gateway_route_table_propagation" "vpc" {
  for_each = {
    for item in flatten([
      for k, v in var.vpc_attachments : [
        for rt_id in lookup(v, "propagate_to_route_tables", []) : {
          attachment_key = k
          route_table_id = rt_id
          unique_key     = "${k}-${rt_id}"
        }
      ]
    ]) : item.unique_key => item
  }

  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this[each.value.attachment_key].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.this[each.value.route_table_id].id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "vpn" {
  for_each = {
    for item in flatten([
      for k, v in var.vpn_attachments : [
        for rt_id in lookup(v, "propagate_to_route_tables", []) : {
          attachment_key = k
          route_table_id = rt_id
          unique_key     = "${k}-${rt_id}"
        }
      ]
    ]) : item.unique_key => item
  }

  transit_gateway_attachment_id  = aws_vpn_connection.this[each.value.attachment_key].transit_gateway_attachment_id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.this[each.value.route_table_id].id
}

#------------------------------------------------------------------------------
# Static Routes
#------------------------------------------------------------------------------
resource "aws_ec2_transit_gateway_route" "this" {
  for_each = {
    for item in flatten([
      for rt_key, rt_config in var.transit_gateway_route_tables : [
        for route in lookup(rt_config, "routes", []) : {
          route_table_key = rt_key
          cidr            = route.destination_cidr_block
          attachment_key  = lookup(route, "attachment_key", null)
          blackhole       = lookup(route, "blackhole", false)
          unique_key      = "${rt_key}-${replace(route.destination_cidr_block, "/", "-")}"
        }
      ]
    ]) : item.unique_key => item
  }

  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.this[each.value.route_table_key].id
  destination_cidr_block         = each.value.cidr
  blackhole                      = each.value.blackhole

  transit_gateway_attachment_id = each.value.attachment_key != null ? (
    contains(keys(var.vpc_attachments), each.value.attachment_key) ?
    aws_ec2_transit_gateway_vpc_attachment.this[each.value.attachment_key].id :
    aws_vpn_connection.this[each.value.attachment_key].transit_gateway_attachment_id
  ) : null
}

#------------------------------------------------------------------------------
# Resource Access Manager (RAM) - Cross-Account Sharing
#------------------------------------------------------------------------------
resource "aws_ram_resource_share" "this" {
  count = var.enable_ram_sharing ? 1 : 0

  name                      = "${local.name_prefix}-tgw-share"
  allow_external_principals = var.ram_allow_external_principals

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-tgw-share"
    }
  )
}

resource "aws_ram_resource_association" "this" {
  count = var.enable_ram_sharing ? 1 : 0

  resource_arn       = aws_ec2_transit_gateway.this.arn
  resource_share_arn = aws_ram_resource_share.this[0].arn
}

resource "aws_ram_principal_association" "this" {
  for_each = var.enable_ram_sharing ? toset(var.ram_principals) : []

  principal          = each.value
  resource_share_arn = aws_ram_resource_share.this[0].arn
}

#------------------------------------------------------------------------------
# Cross-Region Peering
#------------------------------------------------------------------------------
resource "aws_ec2_transit_gateway_peering_attachment" "this" {
  for_each = var.peering_attachments

  peer_region             = each.value.peer_region
  peer_transit_gateway_id = each.value.peer_transit_gateway_id
  transit_gateway_id      = aws_ec2_transit_gateway.this.id

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-tgw-peering-${each.key}"
    }
  )
}
