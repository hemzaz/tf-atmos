locals {
  name_prefix = var.name_prefix

  common_tags = merge(
    {
      Name        = local.name_prefix
      Environment = var.environment
      ManagedBy   = "Terraform"
      Module      = "nat-gateway-ha"
    },
    var.tags
  )

  # One NAT Gateway per AZ for high availability, keyed by AZ (subnet lists
  # are positionally aligned with availability_zones)
  nat_gateway_azs = var.enable_nat_gateway ? slice(var.availability_zones, 0, length(var.public_subnet_ids)) : []
  nat_gateways    = { for i, az in local.nat_gateway_azs : az => var.public_subnet_ids[i] }

  private_subnets = { for i, subnet_id in var.private_subnet_ids : var.availability_zones[i] => subnet_id }

  nat_gateway_count = length(local.nat_gateways)
}

#------------------------------------------------------------------------------
# Elastic IPs for NAT Gateways
#------------------------------------------------------------------------------
resource "aws_eip" "nat" {
  for_each = local.nat_gateways

  domain = "vpc"

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-nat-eip-${each.key}"
      AZ   = each.key
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

#------------------------------------------------------------------------------
# NAT Gateways (One per AZ)
#------------------------------------------------------------------------------
resource "aws_nat_gateway" "this" {
  for_each = local.nat_gateways

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = each.value

  connectivity_type = "public"

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-nat-${each.key}"
      AZ   = each.key
    }
  )

  depends_on = [var.internet_gateway_id]
}

#------------------------------------------------------------------------------
# Private Route Tables (One per AZ)
#------------------------------------------------------------------------------
resource "aws_route_table" "private" {
  for_each = local.private_subnets

  vpc_id = var.vpc_id

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-private-rt-${each.key}"
      Tier = "private"
      AZ   = each.key
    }
  )
}

#------------------------------------------------------------------------------
# Routes to NAT Gateways
#------------------------------------------------------------------------------
resource "aws_route" "private_nat_gateway" {
  for_each = { for az, subnet_id in local.private_subnets : az => subnet_id if contains(keys(local.nat_gateways), az) }

  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[each.key].id

  timeouts {
    create = "5m"
  }
}

#------------------------------------------------------------------------------
# Route Table Associations
#------------------------------------------------------------------------------
resource "aws_route_table_association" "private" {
  for_each = local.private_subnets

  subnet_id      = each.value
  route_table_id = aws_route_table.private[each.key].id
}

#------------------------------------------------------------------------------
# CloudWatch Alarms for NAT Gateway Monitoring
#------------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "nat_gateway_error_port_allocation" {
  for_each = var.enable_cloudwatch_alarms ? local.nat_gateways : {}

  alarm_name          = "${local.name_prefix}-nat-${each.key}-error-port-allocation"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ErrorPortAllocation"
  namespace           = "AWS/NATGateway"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "NAT Gateway port allocation errors in ${each.key}"
  treat_missing_data  = "notBreaching"

  dimensions = {
    NatGatewayId = aws_nat_gateway.this[each.key].id
  }

  alarm_actions = var.alarm_sns_topic_arns

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "nat_gateway_packets_drop" {
  for_each = var.enable_cloudwatch_alarms ? local.nat_gateways : {}

  alarm_name          = "${local.name_prefix}-nat-${each.key}-packets-drop"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "PacketsDropCount"
  namespace           = "AWS/NATGateway"
  period              = 300
  statistic           = "Sum"
  threshold           = 100
  alarm_description   = "NAT Gateway packet drops in ${each.key}"
  treat_missing_data  = "notBreaching"

  dimensions = {
    NatGatewayId = aws_nat_gateway.this[each.key].id
  }

  alarm_actions = var.alarm_sns_topic_arns

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "nat_gateway_bandwidth" {
  for_each = var.enable_cloudwatch_alarms && var.bandwidth_alarm_threshold_mbps > 0 ? local.nat_gateways : {}

  alarm_name          = "${local.name_prefix}-nat-${each.key}-high-bandwidth"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "BytesOutToDestination"
  namespace           = "AWS/NATGateway"
  period              = 300
  statistic           = "Average"
  threshold           = var.bandwidth_alarm_threshold_mbps * 1048576 / 60 # Convert Mbps to bytes per second
  alarm_description   = "NAT Gateway high bandwidth usage in ${each.key}"
  treat_missing_data  = "notBreaching"

  dimensions = {
    NatGatewayId = aws_nat_gateway.this[each.key].id
  }

  alarm_actions = var.alarm_sns_topic_arns

  tags = local.common_tags
}

#------------------------------------------------------------------------------
# Cost Optimization: CloudWatch Dashboard for Monitoring
#------------------------------------------------------------------------------
resource "aws_cloudwatch_dashboard" "nat_gateway" {
  count = var.create_cloudwatch_dashboard ? 1 : 0

  dashboard_name = "${local.name_prefix}-nat-gateways"

  dashboard_body = jsonencode({
    widgets = concat(
      [
        for az in local.nat_gateway_azs : {
          type = "metric"
          properties = {
            metrics = [
              ["AWS/NATGateway", "BytesOutToDestination", "NatGatewayId", aws_nat_gateway.this[az].id, { stat = "Sum", label = "Bytes Out" }],
              [".", "BytesInFromDestination", ".", ".", { stat = "Sum", label = "Bytes In" }],
              [".", "PacketsOutToDestination", ".", ".", { stat = "Sum", label = "Packets Out" }],
              [".", "PacketsInFromDestination", ".", ".", { stat = "Sum", label = "Packets In" }]
            ]
            view   = "timeSeries"
            region = data.aws_region.current.region
            title  = "NAT Gateway ${az} - Data Transfer"
            period = 300
            yAxis = {
              left = {
                label = "Bytes/Packets"
              }
            }
          }
        }
      ],
      [
        {
          type = "metric"
          properties = {
            metrics = [
              for az in local.nat_gateway_azs : [
                "AWS/NATGateway", "ActiveConnectionCount", "NatGatewayId", aws_nat_gateway.this[az].id,
                { stat = "Average", label = az }
              ]
            ]
            view   = "timeSeries"
            region = data.aws_region.current.region
            title  = "NAT Gateway - Active Connections"
            period = 300
          }
        }
      ]
    )
  })
}

data "aws_region" "current" {}
