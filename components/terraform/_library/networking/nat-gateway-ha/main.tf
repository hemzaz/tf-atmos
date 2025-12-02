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

  # Create NAT Gateway per AZ for high availability
  nat_gateway_count = var.enable_nat_gateway ? length(var.public_subnet_ids) : 0
}

#------------------------------------------------------------------------------
# Elastic IPs for NAT Gateways
#------------------------------------------------------------------------------
resource "aws_eip" "nat" {
  count = local.nat_gateway_count

  domain = "vpc"

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-nat-eip-${count.index + 1}"
      AZ   = var.availability_zones[count.index]
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
  count = local.nat_gateway_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = var.public_subnet_ids[count.index]

  connectivity_type = "public"

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-nat-${var.availability_zones[count.index]}"
      AZ   = var.availability_zones[count.index]
    }
  )

  depends_on = [var.internet_gateway_id]
}

#------------------------------------------------------------------------------
# Private Route Tables (One per AZ)
#------------------------------------------------------------------------------
resource "aws_route_table" "private" {
  count = length(var.private_subnet_ids)

  vpc_id = var.vpc_id

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-private-rt-${var.availability_zones[count.index]}"
      Tier = "private"
      AZ   = var.availability_zones[count.index]
    }
  )
}

#------------------------------------------------------------------------------
# Routes to NAT Gateways
#------------------------------------------------------------------------------
resource "aws_route" "private_nat_gateway" {
  count = var.enable_nat_gateway ? length(var.private_subnet_ids) : 0

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[count.index].id

  timeouts {
    create = "5m"
  }
}

#------------------------------------------------------------------------------
# Route Table Associations
#------------------------------------------------------------------------------
resource "aws_route_table_association" "private" {
  count = length(var.private_subnet_ids)

  subnet_id      = var.private_subnet_ids[count.index]
  route_table_id = aws_route_table.private[count.index].id
}

#------------------------------------------------------------------------------
# CloudWatch Alarms for NAT Gateway Monitoring
#------------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "nat_gateway_error_port_allocation" {
  count = var.enable_cloudwatch_alarms ? local.nat_gateway_count : 0

  alarm_name          = "${local.name_prefix}-nat-${var.availability_zones[count.index]}-error-port-allocation"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ErrorPortAllocation"
  namespace           = "AWS/NATGateway"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "NAT Gateway port allocation errors in ${var.availability_zones[count.index]}"
  treat_missing_data  = "notBreaching"

  dimensions = {
    NatGatewayId = aws_nat_gateway.this[count.index].id
  }

  alarm_actions = var.alarm_sns_topic_arns

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "nat_gateway_packets_drop" {
  count = var.enable_cloudwatch_alarms ? local.nat_gateway_count : 0

  alarm_name          = "${local.name_prefix}-nat-${var.availability_zones[count.index]}-packets-drop"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "PacketsDropCount"
  namespace           = "AWS/NATGateway"
  period              = 300
  statistic           = "Sum"
  threshold           = 100
  alarm_description   = "NAT Gateway packet drops in ${var.availability_zones[count.index]}"
  treat_missing_data  = "notBreaching"

  dimensions = {
    NatGatewayId = aws_nat_gateway.this[count.index].id
  }

  alarm_actions = var.alarm_sns_topic_arns

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "nat_gateway_bandwidth" {
  count = var.enable_cloudwatch_alarms && var.bandwidth_alarm_threshold_mbps > 0 ? local.nat_gateway_count : 0

  alarm_name          = "${local.name_prefix}-nat-${var.availability_zones[count.index]}-high-bandwidth"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "BytesOutToDestination"
  namespace           = "AWS/NATGateway"
  period              = 300
  statistic           = "Average"
  threshold           = var.bandwidth_alarm_threshold_mbps * 1048576 / 60 # Convert Mbps to bytes per second
  alarm_description   = "NAT Gateway high bandwidth usage in ${var.availability_zones[count.index]}"
  treat_missing_data  = "notBreaching"

  dimensions = {
    NatGatewayId = aws_nat_gateway.this[count.index].id
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
        for i in range(local.nat_gateway_count) : {
          type = "metric"
          properties = {
            metrics = [
              ["AWS/NATGateway", "BytesOutToDestination", { stat = "Sum", label = "Bytes Out" }],
              [".", "BytesInFromDestination", { stat = "Sum", label = "Bytes In" }],
              [".", "PacketsOutToDestination", { stat = "Sum", label = "Packets Out" }],
              [".", "PacketsInFromDestination", { stat = "Sum", label = "Packets In" }]
            ]
            view    = "timeSeries"
            region  = data.aws_region.current.name
            title   = "NAT Gateway ${var.availability_zones[i]} - Data Transfer"
            period  = 300
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
              for i in range(local.nat_gateway_count) : [
                "AWS/NATGateway", "ActiveConnectionCount",
                { stat = "Average", label = var.availability_zones[i] }
              ]
            ]
            view   = "timeSeries"
            region = data.aws_region.current.name
            title  = "NAT Gateway - Active Connections"
            period = 300
          }
        }
      ]
    )
  })
}

data "aws_region" "current" {}
