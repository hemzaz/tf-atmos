##############################################
# API Gateway REST API
##############################################

locals {
  api_name = "${var.name_prefix}-${var.api_name}"

  tags = merge(
    var.tags,
    {
      Name      = local.api_name
      ManagedBy = "Terraform"
    }
  )
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

##############################################
# REST API
##############################################

resource "aws_api_gateway_rest_api" "main" {
  name        = local.api_name
  description = var.api_description

  endpoint_configuration {
    types = [var.endpoint_type]
    vpc_endpoint_ids = var.endpoint_type == "PRIVATE" ? var.vpc_endpoint_ids : null
  }

  binary_media_types = var.binary_media_types
  minimum_compression_size = var.enable_compression ? var.minimum_compression_size : null

  dynamic "policy" {
    for_each = var.api_policy != null ? [1] : []
    content {
      policy = var.api_policy
    }
  }

  tags = local.tags
}

##############################################
# CloudWatch Log Group for Access Logs
##############################################

resource "aws_cloudwatch_log_group" "api" {
  count = var.enable_access_logging ? 1 : 0

  name              = "/aws/apigateway/${local.api_name}"
  retention_in_days = var.log_retention_days

  tags = local.tags
}

##############################################
# API Gateway Account (for CloudWatch Logs)
##############################################

resource "aws_api_gateway_account" "main" {
  count = var.enable_access_logging && var.create_log_role ? 1 : 0

  cloudwatch_role_arn = aws_iam_role.cloudwatch[0].arn
}

resource "aws_iam_role" "cloudwatch" {
  count = var.enable_access_logging && var.create_log_role ? 1 : 0

  name               = "${local.api_name}-api-gateway-cloudwatch"
  assume_role_policy = data.aws_iam_policy_document.cloudwatch_assume[0].json

  tags = local.tags
}

data "aws_iam_policy_document" "cloudwatch_assume" {
  count = var.enable_access_logging && var.create_log_role ? 1 : 0

  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role_policy_attachment" "cloudwatch" {
  count = var.enable_access_logging && var.create_log_role ? 1 : 0

  role       = aws_iam_role.cloudwatch[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

##############################################
# Deployment and Stage
##############################################

resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id

  triggers = {
    redeployment = var.deployment_trigger
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [aws_api_gateway_rest_api.main]
}

resource "aws_api_gateway_stage" "main" {
  deployment_id = aws_api_gateway_deployment.main.id
  rest_api_id   = aws_api_gateway_rest_api.main.id
  stage_name    = var.stage_name

  xray_tracing_enabled = var.enable_xray_tracing
  cache_cluster_enabled = var.enable_cache
  cache_cluster_size = var.enable_cache ? var.cache_cluster_size : null

  dynamic "access_log_settings" {
    for_each = var.enable_access_logging ? [1] : []
    content {
      destination_arn = aws_cloudwatch_log_group.api[0].arn
      format          = var.access_log_format
    }
  }

  variables = var.stage_variables

  tags = local.tags
}

##############################################
# Method Settings
##############################################

resource "aws_api_gateway_method_settings" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  stage_name  = aws_api_gateway_stage.main.stage_name
  method_path = "*/*"

  settings {
    metrics_enabled        = var.enable_metrics
    logging_level          = var.logging_level
    data_trace_enabled     = var.enable_data_trace
    throttling_burst_limit = var.throttling_burst_limit
    throttling_rate_limit  = var.throttling_rate_limit
    caching_enabled        = var.enable_cache

    # Cache settings
    cache_ttl_in_seconds           = var.enable_cache ? var.cache_ttl_seconds : null
    cache_data_encrypted           = var.enable_cache ? var.cache_data_encrypted : null
    require_authorization_for_cache_control = var.enable_cache ? var.require_authorization_for_cache_control : null
  }
}

##############################################
# API Keys and Usage Plans
##############################################

resource "aws_api_gateway_api_key" "main" {
  for_each = { for key in var.api_keys : key.name => key }

  name        = "${local.api_name}-${each.value.name}"
  description = lookup(each.value, "description", null)
  enabled     = lookup(each.value, "enabled", true)
  value       = lookup(each.value, "value", null)

  tags = local.tags
}

resource "aws_api_gateway_usage_plan" "main" {
  for_each = { for plan in var.usage_plans : plan.name => plan }

  name        = "${local.api_name}-${each.value.name}"
  description = lookup(each.value, "description", null)

  api_stages {
    api_id = aws_api_gateway_rest_api.main.id
    stage  = aws_api_gateway_stage.main.stage_name
  }

  dynamic "quota_settings" {
    for_each = lookup(each.value, "quota_limit", null) != null ? [1] : []
    content {
      limit  = each.value.quota_limit
      offset = lookup(each.value, "quota_offset", 0)
      period = lookup(each.value, "quota_period", "DAY")
    }
  }

  dynamic "throttle_settings" {
    for_each = lookup(each.value, "throttle_burst_limit", null) != null ? [1] : []
    content {
      burst_limit = each.value.throttle_burst_limit
      rate_limit  = each.value.throttle_rate_limit
    }
  }

  tags = local.tags
}

resource "aws_api_gateway_usage_plan_key" "main" {
  for_each = { for assoc in local.usage_plan_key_associations : "${assoc.plan_name}-${assoc.key_name}" => assoc }

  key_id        = aws_api_gateway_api_key.main[each.value.key_name].id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.main[each.value.plan_name].id
}

locals {
  usage_plan_key_associations = flatten([
    for plan in var.usage_plans : [
      for key_name in lookup(plan, "api_key_names", []) : {
        plan_name = plan.name
        key_name  = key_name
      }
    ]
  ])
}

##############################################
# WAF Association
##############################################

resource "aws_wafv2_web_acl_association" "main" {
  count = var.waf_acl_arn != null ? 1 : 0

  resource_arn = aws_api_gateway_stage.main.arn
  web_acl_arn  = var.waf_acl_arn
}

##############################################
# Custom Domain
##############################################

resource "aws_api_gateway_domain_name" "main" {
  count = var.custom_domain_name != null ? 1 : 0

  domain_name              = var.custom_domain_name
  regional_certificate_arn = var.endpoint_type == "REGIONAL" ? var.certificate_arn : null
  certificate_arn          = var.endpoint_type == "EDGE" ? var.certificate_arn : null

  security_policy = var.custom_domain_security_policy

  endpoint_configuration {
    types = [var.endpoint_type]
  }

  tags = local.tags
}

resource "aws_api_gateway_base_path_mapping" "main" {
  count = var.custom_domain_name != null ? 1 : 0

  api_id      = aws_api_gateway_rest_api.main.id
  stage_name  = aws_api_gateway_stage.main.stage_name
  domain_name = aws_api_gateway_domain_name.main[0].domain_name
  base_path   = var.custom_domain_base_path
}

##############################################
# Request Validators
##############################################

resource "aws_api_gateway_request_validator" "main" {
  for_each = { for validator in var.request_validators : validator.name => validator }

  name                        = "${local.api_name}-${each.value.name}"
  rest_api_id                 = aws_api_gateway_rest_api.main.id
  validate_request_body       = lookup(each.value, "validate_request_body", false)
  validate_request_parameters = lookup(each.value, "validate_request_parameters", false)
}

##############################################
# CloudWatch Alarms
##############################################

resource "aws_cloudwatch_metric_alarm" "error_rate" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.api_name}-${var.stage_name}-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "5XXError"
  namespace           = "AWS/ApiGateway"
  period              = var.alarm_period_seconds
  statistic           = "Sum"
  threshold           = var.alarm_5xx_error_threshold
  alarm_description   = "API Gateway 5XX errors for ${local.api_name}"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.alarm_ok_actions

  dimensions = {
    ApiName = aws_api_gateway_rest_api.main.name
    Stage   = aws_api_gateway_stage.main.stage_name
  }

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "latency" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.api_name}-${var.stage_name}-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "Latency"
  namespace           = "AWS/ApiGateway"
  period              = var.alarm_period_seconds
  statistic           = "Average"
  threshold           = var.alarm_latency_threshold
  alarm_description   = "API Gateway high latency for ${local.api_name}"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.alarm_ok_actions

  dimensions = {
    ApiName = aws_api_gateway_rest_api.main.name
    Stage   = aws_api_gateway_stage.main.stage_name
  }

  tags = local.tags
}
