##############################################
# X-Ray Sampling Rules
##############################################

resource "aws_xray_sampling_rule" "default" {
  count = var.create_default_sampling_rule ? 1 : 0

  rule_name      = "${var.name_prefix}-default"
  priority       = 1000
  version        = 1
  reservoir_size = var.default_reservoir_size
  fixed_rate     = var.default_fixed_rate
  url_path       = "*"
  host           = "*"
  http_method    = "*"
  service_type   = "*"
  service_name   = "*"
  resource_arn   = "*"

  tags = merge(
    var.tags,
    {
      Name      = "${var.name_prefix}-default"
      ManagedBy = "terraform"
    }
  )
}

resource "aws_xray_sampling_rule" "high_value" {
  count = var.enable_high_value_sampling ? 1 : 0

  rule_name      = "${var.name_prefix}-high-value"
  priority       = 100
  version        = 1
  reservoir_size = 50
  fixed_rate     = 1.0
  url_path       = var.high_value_url_pattern
  host           = "*"
  http_method    = "*"
  service_type   = "*"
  service_name   = "*"
  resource_arn   = "*"

  tags = merge(
    var.tags,
    {
      Name      = "${var.name_prefix}-high-value"
      Priority  = "high"
      ManagedBy = "terraform"
    }
  )
}

resource "aws_xray_sampling_rule" "custom" {
  for_each = var.custom_sampling_rules

  rule_name      = "${var.name_prefix}-${each.key}"
  priority       = each.value.priority
  version        = 1
  reservoir_size = each.value.reservoir_size
  fixed_rate     = each.value.fixed_rate
  url_path       = lookup(each.value, "url_path", "*")
  host           = lookup(each.value, "host", "*")
  http_method    = lookup(each.value, "http_method", "*")
  service_type   = lookup(each.value, "service_type", "*")
  service_name   = lookup(each.value, "service_name", "*")
  resource_arn   = lookup(each.value, "resource_arn", "*")

  tags = merge(
    var.tags,
    {
      Name      = "${var.name_prefix}-${each.key}"
      ManagedBy = "terraform"
    }
  )
}

##############################################
# X-Ray Groups
##############################################

resource "aws_xray_group" "default" {
  count = var.create_default_group ? 1 : 0

  group_name        = "${var.name_prefix}-all"
  filter_expression = var.default_group_filter

  insights_configuration {
    insights_enabled      = var.enable_insights
    notifications_enabled = var.enable_insights_notifications
  }

  tags = merge(
    var.tags,
    {
      Name      = "${var.name_prefix}-all"
      ManagedBy = "terraform"
    }
  )
}

resource "aws_xray_group" "errors" {
  count = var.create_error_group ? 1 : 0

  group_name        = "${var.name_prefix}-errors"
  filter_expression = "error = true OR fault = true"

  insights_configuration {
    insights_enabled      = var.enable_insights
    notifications_enabled = var.enable_insights_notifications
  }

  tags = merge(
    var.tags,
    {
      Name      = "${var.name_prefix}-errors"
      Type      = "error-tracking"
      ManagedBy = "terraform"
    }
  )
}

resource "aws_xray_group" "slow_requests" {
  count = var.create_slow_requests_group ? 1 : 0

  group_name        = "${var.name_prefix}-slow-requests"
  filter_expression = "responsetime > ${var.slow_request_threshold}"

  insights_configuration {
    insights_enabled      = var.enable_insights
    notifications_enabled = var.enable_insights_notifications
  }

  tags = merge(
    var.tags,
    {
      Name      = "${var.name_prefix}-slow-requests"
      Type      = "performance-tracking"
      ManagedBy = "terraform"
    }
  )
}

resource "aws_xray_group" "custom" {
  for_each = var.custom_groups

  group_name        = "${var.name_prefix}-${each.key}"
  filter_expression = each.value.filter_expression

  insights_configuration {
    insights_enabled      = var.enable_insights
    notifications_enabled = var.enable_insights_notifications
  }

  tags = merge(
    var.tags,
    {
      Name      = "${var.name_prefix}-${each.key}"
      ManagedBy = "terraform"
    }
  )
}

##############################################
# Lambda X-Ray Configuration
##############################################

resource "aws_lambda_function_event_invoke_config" "xray" {
  for_each = var.enable_lambda_integration ? toset(var.lambda_function_names) : []

  function_name = each.value

  destination_config {
    on_success {
      destination = var.lambda_success_destination
    }

    on_failure {
      destination = var.lambda_failure_destination
    }
  }

  maximum_retry_attempts = 0
}

##############################################
# API Gateway X-Ray Integration
##############################################

data "aws_api_gateway_rest_api" "integration" {
  for_each = var.enable_api_gateway_integration ? toset(var.api_gateway_names) : []
  name     = each.value
}

resource "aws_api_gateway_stage" "xray" {
  for_each = var.enable_api_gateway_integration ? toset(var.api_gateway_names) : []

  deployment_id        = data.aws_api_gateway_rest_api.integration[each.key].id
  rest_api_id          = data.aws_api_gateway_rest_api.integration[each.key].id
  stage_name           = var.api_gateway_stage_name
  xray_tracing_enabled = true

  tags = merge(
    var.tags,
    {
      XRayEnabled = "true"
      ManagedBy   = "terraform"
    }
  )
}

##############################################
# Cost Optimization - Sampling Strategy
##############################################

locals {
  # Cost-optimized sampling rates by environment
  sampling_rate = var.enable_cost_optimization ? {
    production  = 0.05  # 5% sampling in prod
    staging     = 0.20  # 20% sampling in staging
    development = 1.0   # 100% sampling in dev
  }[var.environment] : var.default_fixed_rate

  # Intelligent reservoir sizing
  reservoir_size = var.enable_cost_optimization ? {
    production  = 1   # Keep at least 1 trace per second
    staging     = 5   # Keep at least 5 traces per second
    development = 10  # Keep at least 10 traces per second
  }[var.environment] : var.default_reservoir_size
}

##############################################
# CloudWatch Alarms for X-Ray
##############################################

resource "aws_cloudwatch_metric_alarm" "trace_error_rate" {
  count = var.create_trace_alarms ? 1 : 0

  alarm_name          = "${var.name_prefix}-trace-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ErrorRate"
  namespace           = "AWS/XRay"
  period              = 300
  statistic           = "Average"
  threshold           = var.error_rate_threshold
  alarm_description   = "X-Ray trace error rate exceeds threshold"
  alarm_actions       = var.alarm_actions

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-trace-error-rate"
    }
  )
}

##############################################
# Data Sources
##############################################

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
