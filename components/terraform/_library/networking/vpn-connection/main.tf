locals {
  name_prefix = var.name_prefix

  common_tags = merge(
    {
      Name        = local.name_prefix
      Environment = var.environment
      ManagedBy   = "Terraform"
      Module      = "vpn-connection"
    },
    var.tags
  )
}

#------------------------------------------------------------------------------
# Customer Gateway
#------------------------------------------------------------------------------
resource "aws_customer_gateway" "this" {
  bgp_asn    = var.customer_gateway_bgp_asn
  ip_address = var.customer_gateway_ip_address
  type       = "ipsec.1"

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-cgw"
    }
  )
}

#------------------------------------------------------------------------------
# Virtual Private Gateway
#------------------------------------------------------------------------------
resource "aws_vpn_gateway" "this" {
  count = var.use_transit_gateway ? 0 : 1

  vpc_id          = var.vpc_id
  amazon_side_asn = var.vpn_gateway_amazon_side_asn

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-vgw"
    }
  )
}

resource "aws_vpn_gateway_attachment" "this" {
  count = var.use_transit_gateway ? 0 : 1

  vpc_id         = var.vpc_id
  vpn_gateway_id = aws_vpn_gateway.this[0].id
}

#------------------------------------------------------------------------------
# VPN Connection
#------------------------------------------------------------------------------
resource "aws_vpn_connection" "this" {
  customer_gateway_id = aws_customer_gateway.this.id
  type                = "ipsec.1"

  # Use either Transit Gateway or Virtual Private Gateway
  transit_gateway_id  = var.use_transit_gateway ? var.transit_gateway_id : null
  vpn_gateway_id      = var.use_transit_gateway ? null : aws_vpn_gateway.this[0].id

  static_routes_only = var.static_routes_only

  # Tunnel configuration
  tunnel1_inside_cidr   = var.tunnel1_inside_cidr
  tunnel1_preshared_key = var.tunnel1_preshared_key
  tunnel1_dpd_timeout_action = var.tunnel1_dpd_timeout_action
  tunnel1_ike_versions  = var.tunnel1_ike_versions
  tunnel1_phase1_dh_group_numbers = var.tunnel1_phase1_dh_group_numbers
  tunnel1_phase1_encryption_algorithms = var.tunnel1_phase1_encryption_algorithms
  tunnel1_phase1_integrity_algorithms = var.tunnel1_phase1_integrity_algorithms
  tunnel1_phase1_lifetime_seconds = var.tunnel1_phase1_lifetime_seconds
  tunnel1_phase2_dh_group_numbers = var.tunnel1_phase2_dh_group_numbers
  tunnel1_phase2_encryption_algorithms = var.tunnel1_phase2_encryption_algorithms
  tunnel1_phase2_integrity_algorithms = var.tunnel1_phase2_integrity_algorithms
  tunnel1_phase2_lifetime_seconds = var.tunnel1_phase2_lifetime_seconds
  tunnel1_startup_action = var.tunnel1_startup_action

  tunnel2_inside_cidr   = var.tunnel2_inside_cidr
  tunnel2_preshared_key = var.tunnel2_preshared_key
  tunnel2_dpd_timeout_action = var.tunnel2_dpd_timeout_action
  tunnel2_ike_versions  = var.tunnel2_ike_versions
  tunnel2_phase1_dh_group_numbers = var.tunnel2_phase1_dh_group_numbers
  tunnel2_phase1_encryption_algorithms = var.tunnel2_phase1_encryption_algorithms
  tunnel2_phase1_integrity_algorithms = var.tunnel2_phase1_integrity_algorithms
  tunnel2_phase1_lifetime_seconds = var.tunnel2_phase1_lifetime_seconds
  tunnel2_phase2_dh_group_numbers = var.tunnel2_phase2_dh_group_numbers
  tunnel2_phase2_encryption_algorithms = var.tunnel2_phase2_encryption_algorithms
  tunnel2_phase2_integrity_algorithms = var.tunnel2_phase2_integrity_algorithms
  tunnel2_phase2_lifetime_seconds = var.tunnel2_phase2_lifetime_seconds
  tunnel2_startup_action = var.tunnel2_startup_action

  # Logging
  tunnel1_log_options {
    cloudwatch_log_group_arn = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.tunnel1[0].arn : null
  }

  tunnel2_log_options {
    cloudwatch_log_group_arn = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.tunnel2[0].arn : null
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-vpn"
    }
  )
}

#------------------------------------------------------------------------------
# Static Routes (if static routing is enabled)
#------------------------------------------------------------------------------
resource "aws_vpn_connection_route" "this" {
  for_each = var.static_routes_only ? var.static_routes : {}

  vpn_connection_id      = aws_vpn_connection.this.id
  destination_cidr_block = each.value
}

#------------------------------------------------------------------------------
# VPN Gateway Route Propagation (for VGW mode)
#------------------------------------------------------------------------------
resource "aws_vpn_gateway_route_propagation" "this" {
  for_each = var.use_transit_gateway ? {} : var.route_table_ids

  vpn_gateway_id = aws_vpn_gateway.this[0].id
  route_table_id = each.value
}

#------------------------------------------------------------------------------
# CloudWatch Logs
#------------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "tunnel1" {
  count = var.enable_cloudwatch_logs ? 1 : 0

  name              = "/aws/vpn/${local.name_prefix}-tunnel1"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-vpn-tunnel1-logs"
    }
  )
}

resource "aws_cloudwatch_log_group" "tunnel2" {
  count = var.enable_cloudwatch_logs ? 1 : 0

  name              = "/aws/vpn/${local.name_prefix}-tunnel2"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-vpn-tunnel2-logs"
    }
  )
}

#------------------------------------------------------------------------------
# CloudWatch Alarms
#------------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "tunnel1_state" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.name_prefix}-vpn-tunnel1-down"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "TunnelState"
  namespace           = "AWS/VPN"
  period              = 300
  statistic           = "Maximum"
  threshold           = 1
  alarm_description   = "VPN Tunnel 1 is down"
  treat_missing_data  = "breaching"

  dimensions = {
    VpnId = aws_vpn_connection.this.id
  }

  alarm_actions = var.alarm_sns_topic_arns
  ok_actions    = var.alarm_sns_topic_arns

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "tunnel2_state" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.name_prefix}-vpn-tunnel2-down"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "TunnelState"
  namespace           = "AWS/VPN"
  period              = 300
  statistic           = "Maximum"
  threshold           = 1
  alarm_description   = "VPN Tunnel 2 is down"
  treat_missing_data  = "breaching"

  dimensions = {
    VpnId = aws_vpn_connection.this.id
  }

  alarm_actions = var.alarm_sns_topic_arns
  ok_actions    = var.alarm_sns_topic_arns

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "tunnel1_data_in" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.name_prefix}-vpn-tunnel1-no-data-in"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 3
  metric_name         = "TunnelDataIn"
  namespace           = "AWS/VPN"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "VPN Tunnel 1 has no incoming data"
  treat_missing_data  = "notBreaching"

  dimensions = {
    VpnId = aws_vpn_connection.this.id
  }

  alarm_actions = var.alarm_sns_topic_arns

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "tunnel2_data_in" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.name_prefix}-vpn-tunnel2-no-data-in"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 3
  metric_name         = "TunnelDataIn"
  namespace           = "AWS/VPN"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "VPN Tunnel 2 has no incoming data"
  treat_missing_data  = "notBreaching"

  dimensions = {
    VpnId = aws_vpn_connection.this.id
  }

  alarm_actions = var.alarm_sns_topic_arns

  tags = local.common_tags
}
