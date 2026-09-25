locals {
  enabled = var.enabled

  # Environment-based name prefix for consistent naming across all components.
  #
  # KEEP the try(). var.tags is validated to carry a non-empty Environment, so
  # the fallback is unreachable at plan and apply time and reads like dead code
  # - but tflint evaluates these locals statically, without resolving var.tags,
  # and a bare var.tags["Environment"] makes it abort the
  # aws_cloudwatch_log_group_invalid_name rule with "Failed to check ruleset",
  # failing `atmos workflow lint` on both apigateway instances. Removing it was
  # tried and reverted. The directory tflint pass does NOT catch this; only the
  # per-instance pass does.
  environment = try(var.tags["Environment"], "default")
  name_prefix = "${local.environment}-${var.api_name}"

  # Determine which API type to create based on var.api_type
  create_rest_api = local.enabled && var.api_type == "REST"
  create_http_api = local.enabled && var.api_type == "HTTP"

  # Default tags
  default_tags = {
    Name        = local.name_prefix
    ApiType     = var.api_type
    Component   = "ApiGateway"
    ManagedBy   = "Terraform"
    Environment = local.environment
  }

  tags = merge(var.tags, local.default_tags)

  # Domain configuration
  domain_enabled = var.domain_name != null && var.certificate_arn != null

  # Logging configuration 
  logs_enabled = var.enable_logging

  # CORS applies to HTTP APIs (REST APIs answer OPTIONS through their methods).
  # This used to look up an "enabled" key the object type does not have, so
  # it was always false and no HTTP API ever got the CORS a stack set.
  enable_cors = local.create_http_api && var.cors_configuration != null

  create_vpc_link = local.create_http_api && length(var.vpc_link_subnet_ids) > 0

  # Resource path -> API Gateway resource id. Stacks declare methods and integrations
  # by path because they cannot know these ids before apply. "/" is the API root.
  api_resource_ids_by_path = merge(
    { for api in aws_api_gateway_rest_api.rest_api : "/" => api.root_resource_id },
    { for idx, res in aws_api_gateway_resource.resource : "/${var.api_resources[idx].path_part}" => res.id }
  )

  # Methods and integrations share one key so each method is paired with its integration.
  api_methods      = { for m in var.api_methods : "${m.http_method} ${m.resource_path}" => m }
  api_integrations = { for i in var.api_integrations : "${i.http_method} ${i.resource_path}" => i }
}

# REST API
resource "aws_api_gateway_rest_api" "rest_api" {
  count = local.create_rest_api ? 1 : 0

  name        = local.name_prefix
  description = var.description

  endpoint_configuration {
    types = var.endpoint_type
  }

  minimum_compression_size = var.minimum_compression_size
  api_key_source           = var.api_key_source
  binary_media_types       = var.binary_media_types

  tags = local.tags
}

# REST API Stage
resource "aws_api_gateway_stage" "rest_stage" {
  #checkov:skip=CKV_AWS_73:Deliberate, not a false positive. X-Ray bills per recorded trace, so tracing_enabled defaults to false and prod opts in (orgs/fnx/prod/.../services.yaml). Revisit if dev/staging ever need distributed tracing.
  count = local.create_rest_api ? 1 : 0

  deployment_id = aws_api_gateway_deployment.rest_deployment[0].id
  rest_api_id   = aws_api_gateway_rest_api.rest_api[0].id
  stage_name    = var.stage_name

  dynamic "access_log_settings" {
    for_each = local.logs_enabled ? [1] : []
    content {
      destination_arn = aws_cloudwatch_log_group.api_logs[0].arn
      format          = var.log_format
    }
  }

  xray_tracing_enabled = var.tracing_enabled

  tags = local.tags
}

# REST API Deployment
resource "aws_api_gateway_deployment" "rest_deployment" {
  count = local.create_rest_api ? 1 : 0

  rest_api_id = aws_api_gateway_rest_api.rest_api[0].id

  # Without a trigger the deployment is created once and never refreshed, so methods
  # added or changed later exist on the API but are never served on the stage.
  triggers = {
    redeployment = sha1(jsonencode([var.api_resources, var.api_methods, var.api_integrations]))
  }

  lifecycle {
    create_before_destroy = true
  }

  # This ensures deployment happens after all the API resources are created
  depends_on = [
    aws_api_gateway_method.method,
    aws_api_gateway_integration.integration
  ]
}

# HTTP API
resource "aws_apigatewayv2_api" "http_api" {
  count = local.create_http_api ? 1 : 0

  name          = local.name_prefix
  protocol_type = "HTTP"
  description   = var.description

  # Only add CORS configuration if enabled
  dynamic "cors_configuration" {
    for_each = local.enable_cors ? [1] : []
    content {
      allow_origins     = var.cors_configuration.allow_origins
      allow_methods     = var.cors_configuration.allow_methods
      allow_headers     = var.cors_configuration.allow_headers
      expose_headers    = var.cors_configuration.expose_headers
      max_age           = var.cors_configuration.max_age
      allow_credentials = var.cors_configuration.allow_credentials
    }
  }

  tags = local.tags
}

# HTTP API Stage
resource "aws_apigatewayv2_stage" "http_stage" {
  count = local.create_http_api ? 1 : 0

  api_id      = aws_apigatewayv2_api.http_api[0].id
  name        = var.stage_name
  auto_deploy = var.auto_deploy

  # Stage-wide throttling. throttling_* used to reach only REST stages.
  default_route_settings {
    throttling_burst_limit = var.throttling_burst_limit
    throttling_rate_limit  = var.throttling_rate_limit
  }

  dynamic "access_log_settings" {
    for_each = local.logs_enabled ? [1] : []
    content {
      destination_arn = aws_cloudwatch_log_group.api_logs[0].arn
      format          = var.log_format
    }
  }

  tags = local.tags
}

# VPC link: lets HTTP API routes reach private load balancers and services
# in the VPC. Routes and integrations that use it are defined outside this
# component (the target listener usually is not known to Terraform).
resource "aws_apigatewayv2_vpc_link" "http" {
  count = local.create_vpc_link ? 1 : 0

  name               = "${local.name_prefix}-vpc-link"
  subnet_ids         = var.vpc_link_subnet_ids
  security_group_ids = var.vpc_link_security_group_ids

  tags = merge(local.tags, { Name = "${local.name_prefix}-vpc-link" })
}

# Custom Domain Name for REST API
resource "aws_api_gateway_domain_name" "rest_domain" {
  count = local.create_rest_api && local.domain_enabled ? 1 : 0

  domain_name              = var.domain_name
  regional_certificate_arn = var.certificate_arn
  security_policy          = "TLS_1_2"

  endpoint_configuration {
    types = var.endpoint_type
  }

  tags = local.tags

  # regional_certificate_arn only works with a REGIONAL endpoint. EDGE needs
  # certificate_arn (us-east-1) instead, and PRIVATE does not support a
  # regional custom domain at all; either would plan fine here and fail at
  # apply. Real stacks are unaffected: both apigateway/main and
  # apigateway/data use the REGIONAL default.
  lifecycle {
    precondition {
      # `var.endpoint_type == ["REGIONAL"]` is unreliable here: the variable
      # is list(string) and the literal is a tuple, and Terraform's `==`
      # does not treat those as equal even with identical elements.
      condition     = length(var.endpoint_type) == 1 && var.endpoint_type[0] == "REGIONAL"
      error_message = "A REST API custom domain (domain_name + certificate_arn) requires endpoint_type = [\"REGIONAL\"]; got ${jsonencode(var.endpoint_type)}."
    }
  }
}

# Custom Domain Name for HTTP API
resource "aws_apigatewayv2_domain_name" "http_domain" {
  count = local.create_http_api && local.domain_enabled ? 1 : 0

  domain_name = var.domain_name

  domain_name_configuration {
    certificate_arn = var.certificate_arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }

  tags = local.tags
}

# API Mapping for REST API
resource "aws_api_gateway_base_path_mapping" "rest_mapping" {
  count = local.create_rest_api && local.domain_enabled ? 1 : 0

  api_id      = aws_api_gateway_rest_api.rest_api[0].id
  stage_name  = aws_api_gateway_stage.rest_stage[0].stage_name
  domain_name = aws_api_gateway_domain_name.rest_domain[0].domain_name
  base_path   = var.base_path
}

# API Mapping for HTTP API
resource "aws_apigatewayv2_api_mapping" "http_mapping" {
  count = local.create_http_api && local.domain_enabled ? 1 : 0

  api_id          = aws_apigatewayv2_api.http_api[0].id
  stage           = aws_apigatewayv2_stage.http_stage[0].id
  domain_name     = aws_apigatewayv2_domain_name.http_domain[0].domain_name
  api_mapping_key = var.base_path
}

# CloudWatch Log Group for API Gateway
resource "aws_cloudwatch_log_group" "api_logs" {
  count = local.logs_enabled ? 1 : 0

  name              = "/aws/apigateway/${local.name_prefix}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_id

  tags = local.tags
}

# Usage Plan for REST API
resource "aws_api_gateway_usage_plan" "usage_plan" {
  count = local.create_rest_api && var.create_usage_plan ? 1 : 0

  name        = "${local.name_prefix}-usage-plan"
  description = "Usage plan for ${local.name_prefix} API"

  api_stages {
    api_id = aws_api_gateway_rest_api.rest_api[0].id
    stage  = aws_api_gateway_stage.rest_stage[0].stage_name
  }

  quota_settings {
    limit  = var.usage_plan_quota_limit
    offset = var.usage_plan_quota_offset
    period = var.usage_plan_quota_period
  }

  throttle_settings {
    burst_limit = var.usage_plan_throttle_burst_limit
    rate_limit  = var.usage_plan_throttle_rate_limit
  }

  tags = local.tags
}

# API Key for REST API
resource "aws_api_gateway_api_key" "api_key" {
  count = local.create_rest_api && var.create_api_key ? 1 : 0

  name        = "${local.name_prefix}-key"
  description = "API key for ${local.name_prefix}"
  enabled     = true

  tags = local.tags
}

# Usage Plan Key for REST API
resource "aws_api_gateway_usage_plan_key" "usage_plan_key" {
  count = local.create_rest_api && var.create_usage_plan && var.create_api_key ? 1 : 0

  key_id        = aws_api_gateway_api_key.api_key[0].id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.usage_plan[0].id
}

# REST API Authorizer (Cognito)
resource "aws_api_gateway_authorizer" "rest_cognito" {
  count = local.create_rest_api && var.authorizer_type == "COGNITO_USER_POOLS" ? 1 : 0

  name            = "${local.name_prefix}-cognito-authorizer"
  rest_api_id     = aws_api_gateway_rest_api.rest_api[0].id
  type            = "COGNITO_USER_POOLS"
  provider_arns   = var.cognito_user_pool_arns
  identity_source = var.authorizer_identity_source
}

# REST API Authorizer (Lambda)
resource "aws_api_gateway_authorizer" "rest_lambda" {
  count = local.create_rest_api && var.authorizer_type == "TOKEN" ? 1 : 0

  name                   = "${local.name_prefix}-lambda-authorizer"
  rest_api_id            = aws_api_gateway_rest_api.rest_api[0].id
  type                   = "TOKEN"
  authorizer_uri         = var.lambda_authorizer_uri
  identity_source        = var.authorizer_identity_source
  authorizer_credentials = var.lambda_authorizer_role_arn
}

# HTTP API Authorizer (JWT)
resource "aws_apigatewayv2_authorizer" "http_jwt" {
  count = local.create_http_api && var.authorizer_type == "JWT" ? 1 : 0

  api_id           = aws_apigatewayv2_api.http_api[0].id
  authorizer_type  = "JWT"
  name             = "${local.name_prefix}-jwt-authorizer"
  identity_sources = [var.authorizer_identity_source]

  jwt_configuration {
    audience = var.jwt_audience
    issuer   = var.jwt_issuer
  }
}

# HTTP API Authorizer (Lambda)
resource "aws_apigatewayv2_authorizer" "http_lambda" {
  count = local.create_http_api && var.authorizer_type == "REQUEST" ? 1 : 0

  api_id           = aws_apigatewayv2_api.http_api[0].id
  authorizer_type  = "REQUEST"
  name             = "${local.name_prefix}-lambda-authorizer"
  authorizer_uri   = var.lambda_authorizer_uri
  identity_sources = [var.authorizer_identity_source]

  authorizer_payload_format_version = "2.0"
  enable_simple_responses           = true
}

# API Gateway resources
resource "aws_api_gateway_resource" "resource" {
  count = local.create_rest_api && length(var.api_resources) > 0 ? length(var.api_resources) : 0

  rest_api_id = aws_api_gateway_rest_api.rest_api[0].id
  parent_id   = var.api_resources[count.index].parent_id == null ? aws_api_gateway_rest_api.rest_api[0].root_resource_id : var.api_resources[count.index].parent_id
  path_part   = var.api_resources[count.index].path_part
}

# API Gateway methods, keyed by "<HTTP_METHOD> <resource_path>"
resource "aws_api_gateway_method" "method" {
  for_each = local.create_rest_api ? local.api_methods : {}

  rest_api_id   = aws_api_gateway_rest_api.rest_api[0].id
  resource_id   = local.api_resource_ids_by_path[each.value.resource_path]
  http_method   = each.value.http_method
  authorization = each.value.authorization

  # A method may name its own authorizer; otherwise it uses this component's authorizer.
  authorizer_id = each.value.authorizer_id != null ? each.value.authorizer_id : (
    each.value.authorization == "COGNITO_USER_POOLS" ? one(aws_api_gateway_authorizer.rest_cognito[*].id) : (
      each.value.authorization == "CUSTOM" ? one(aws_api_gateway_authorizer.rest_lambda[*].id) : null
    )
  )

  api_key_required = each.value.api_key_required

  request_parameters = each.value.request_parameters
}

# API Gateway integrations, one per method, sharing the method's key
resource "aws_api_gateway_integration" "integration" {
  for_each = local.create_rest_api ? local.api_integrations : {}

  rest_api_id             = aws_api_gateway_rest_api.rest_api[0].id
  resource_id             = local.api_resource_ids_by_path[each.value.resource_path]
  http_method             = each.value.http_method
  integration_http_method = each.value.integration_http_method
  type                    = each.value.type
  uri                     = each.value.uri

  connection_type      = each.value.connection_type
  connection_id        = each.value.connection_id
  timeout_milliseconds = each.value.timeout_milliseconds

  request_parameters = each.value.request_parameters
  request_templates  = each.value.request_templates

  # api_methods validates that every method has an integration; this catches the
  # other direction, an integration naming a method that was never declared.
  lifecycle {
    precondition {
      condition     = contains(keys(local.api_methods), each.key)
      error_message = "api_integrations entry \"${each.key}\" has no matching api_methods entry with the same http_method and resource_path."
    }
  }

  depends_on = [aws_api_gateway_method.method]
}

# Resource policy letting this API invoke the Lambda behind each AWS_PROXY
# integration. Without it the integration applies cleanly and every request
# returns 500 with AccessDeniedException, visible only in the execution log -
# so it is created here rather than left to the caller to remember.
#
# It lives in this component, not in `lambda`, to keep the dependency one-way.
# The lambda component can attach the same permission itself via
# api_gateway_source_arn, but that needs this API's execution_arn while this
# API needs the function's invoke_arn: a cycle. In this direction apigateway
# depends on lambda and nothing depends back.
resource "aws_lambda_permission" "api_gateway_invoke" {
  for_each = local.create_rest_api ? {
    for k, i in local.api_integrations : k => i
    if i.type == "AWS_PROXY"
  } : {}

  statement_id  = "AllowInvokeFrom-${replace(replace(each.key, " ", "-"), "/", "_")}"
  action        = "lambda:InvokeFunction"
  function_name = each.value.lambda_function_name
  principal     = "apigateway.amazonaws.com"

  # Scoped to this API across its stages and methods. Pinning the method and
  # path instead would break on ANY, whose wildcard is not a literal method in
  # a source_arn.
  source_arn = "${aws_api_gateway_rest_api.rest_api[0].execution_arn}/*/*"
}

# Route53 Record for custom domain
resource "aws_route53_record" "api_domain" {
  #checkov:skip=CKV2_AWS_23:False positive, the alias targets this module's API Gateway custom domain
  count = local.domain_enabled && var.zone_id != null ? 1 : 0

  zone_id = var.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = local.create_rest_api ? aws_api_gateway_domain_name.rest_domain[0].regional_domain_name : aws_apigatewayv2_domain_name.http_domain[0].domain_name_configuration[0].target_domain_name
    zone_id                = local.create_rest_api ? aws_api_gateway_domain_name.rest_domain[0].regional_zone_id : aws_apigatewayv2_domain_name.http_domain[0].domain_name_configuration[0].hosted_zone_id
    evaluate_target_health = false
  }
}

# WAF for API Gateway protection
resource "aws_wafv2_web_acl" "api_waf" {
  count = var.enable_waf ? 1 : 0

  name  = "${local.name_prefix}-waf"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.name_prefix}-waf"
    sampled_requests_enabled   = true
  }

  # Rate limiting rule
  rule {
    name     = "RateLimitRule"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.waf_rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}RateLimitRule"
      sampled_requests_enabled   = true
    }
  }

  # Geographic restriction rule
  dynamic "rule" {
    for_each = length(var.allowed_countries) > 0 ? [1] : []
    content {
      name     = "GeographicRule"
      priority = 2

      action {
        block {}
      }

      statement {
        not_statement {
          statement {
            geo_match_statement {
              country_codes = var.allowed_countries
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${local.name_prefix}GeographicRule"
        sampled_requests_enabled   = true
      }
    }
  }

  # AWS Managed Rules
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 10

    override_action {
      dynamic "none" {
        for_each = var.waf_common_rule_set_action == "block" ? [1] : []
        content {}
      }
      dynamic "count" {
        for_each = var.waf_common_rule_set_action == "count" ? [1] : []
        content {}
      }
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}CommonRuleSetMetric"
      sampled_requests_enabled   = true
    }
  }

  # Blocks request patterns of known exploits such as Log4j (CVE-2021-44228)
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 20

    override_action {
      dynamic "none" {
        for_each = var.waf_known_bad_inputs_action == "block" ? [1] : []
        content {}
      }
      dynamic "count" {
        for_each = var.waf_known_bad_inputs_action == "count" ? [1] : []
        content {}
      }
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}KnownBadInputsRuleSetMetric"
      sampled_requests_enabled   = true
    }
  }

  tags = local.tags
}

# Associate WAF with API Gateway
resource "aws_wafv2_web_acl_association" "api_waf_association" {
  count = local.create_rest_api && var.enable_waf ? 1 : 0

  resource_arn = aws_api_gateway_stage.rest_stage[0].arn
  web_acl_arn  = aws_wafv2_web_acl.api_waf[0].arn
}

# API Gateway caching
resource "aws_api_gateway_method_settings" "cache_settings" {
  count = local.create_rest_api && var.enable_caching ? 1 : 0

  rest_api_id = aws_api_gateway_rest_api.rest_api[0].id
  stage_name  = aws_api_gateway_stage.rest_stage[0].stage_name
  method_path = "*/*"

  settings {
    # Enable caching
    caching_enabled      = true
    cache_ttl_in_seconds = var.cache_ttl_seconds

    # Throttling settings
    throttling_rate_limit  = var.throttling_rate_limit
    throttling_burst_limit = var.throttling_burst_limit

    # Logging settings
    logging_level      = var.logging_level
    data_trace_enabled = var.data_trace_enabled
    metrics_enabled    = var.metrics_enabled
  }
}

# CloudWatch Dashboard for API Gateway
resource "aws_cloudwatch_dashboard" "api_dashboard" {
  count = var.create_dashboard ? 1 : 0

  dashboard_name = "${local.name_prefix}-dashboard"

  dashboard_body = templatefile(
    "${path.module}/templates/dashboard.json.tpl",
    {
      api_name    = local.name_prefix
      region      = var.region
      environment = local.environment
      stage_name  = var.stage_name
      api_type    = var.api_type
      api_stages  = [var.stage_name]
      rest_api_id = local.create_rest_api ? aws_api_gateway_rest_api.rest_api[0].id : ""
      http_api_id = local.create_http_api ? aws_apigatewayv2_api.http_api[0].id : ""
    }
  )
}

# Enhanced CloudWatch Alarms for API performance
resource "aws_cloudwatch_metric_alarm" "api_4xx_errors" {
  count = var.create_performance_alarms ? 1 : 0

  alarm_name          = "${local.name_prefix}-4xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "4XXError"
  namespace           = "AWS/ApiGateway"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.alarm_4xx_threshold
  alarm_description   = "This metric monitors 4xx errors on ${local.name_prefix} API"
  alarm_actions       = var.sns_topic_arn != null ? [var.sns_topic_arn] : []

  dimensions = {
    ApiName = local.name_prefix
    Stage   = var.stage_name
  }

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "api_5xx_errors" {
  count = var.create_performance_alarms ? 1 : 0

  alarm_name          = "${local.name_prefix}-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "5XXError"
  namespace           = "AWS/ApiGateway"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.alarm_5xx_threshold
  alarm_description   = "This metric monitors 5xx errors on ${local.name_prefix} API"
  alarm_actions       = var.sns_topic_arn != null ? [var.sns_topic_arn] : []

  dimensions = {
    ApiName = local.name_prefix
    Stage   = var.stage_name
  }

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "api_latency" {
  count = var.create_performance_alarms ? 1 : 0

  alarm_name          = "${local.name_prefix}-high-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Latency"
  namespace           = "AWS/ApiGateway"
  period              = "300"
  statistic           = "Average"
  threshold           = var.alarm_latency_threshold
  alarm_description   = "This metric monitors latency on ${local.name_prefix} API"
  alarm_actions       = var.sns_topic_arn != null ? [var.sns_topic_arn] : []

  dimensions = {
    ApiName = local.name_prefix
    Stage   = var.stage_name
  }

  tags = local.tags
}