locals {
  enabled = var.enabled

  # Name prefix for resources
  name_prefix = var.api_name

  # Determine which API type to create based on var.api_type
  create_rest_api = local.enabled && var.api_type == "REST"
  create_http_api = local.enabled && var.api_type == "HTTP"

  # Default tags
  default_tags = {
    Name      = local.name_prefix
    ApiType   = var.api_type
    Component = "ApiGateway"
    ManagedBy = "Terraform"
  }

  tags = merge(var.tags, local.default_tags)

  # Domain configuration
  domain_enabled = var.domain_name != null && var.certificate_arn != null

  # Logging configuration 
  logs_enabled = var.enable_logging
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

  cors_configuration {
    allow_origins     = var.cors_configuration.allow_origins
    allow_methods     = var.cors_configuration.allow_methods
    allow_headers     = var.cors_configuration.allow_headers
    expose_headers    = var.cors_configuration.expose_headers
    max_age           = var.cors_configuration.max_age
    allow_credentials = var.cors_configuration.allow_credentials
  }

  tags = local.tags
}

# HTTP API Stage
resource "aws_apigatewayv2_stage" "http_stage" {
  count = local.create_http_api ? 1 : 0

  api_id      = aws_apigatewayv2_api.http_api[0].id
  name        = var.stage_name
  auto_deploy = var.auto_deploy

  dynamic "access_log_settings" {
    for_each = local.logs_enabled ? [1] : []
    content {
      destination_arn = aws_cloudwatch_log_group.api_logs[0].arn
      format          = var.log_format
    }
  }

  tags = local.tags
}

# Custom Domain Name for REST API
resource "aws_api_gateway_domain_name" "rest_domain" {
  count = local.create_rest_api && local.domain_enabled ? 1 : 0

  domain_name              = var.domain_name
  regional_certificate_arn = var.certificate_arn

  endpoint_configuration {
    types = var.endpoint_type
  }

  tags = local.tags
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

# API Gateway methods
resource "aws_api_gateway_method" "method" {
  count = local.create_rest_api && length(var.api_methods) > 0 ? length(var.api_methods) : 0

  rest_api_id   = aws_api_gateway_rest_api.rest_api[0].id
  resource_id   = var.api_methods[count.index].resource_id
  http_method   = var.api_methods[count.index].http_method
  authorization = var.api_methods[count.index].authorization

  authorizer_id = var.api_methods[count.index].authorization == "COGNITO_USER_POOLS" ? aws_api_gateway_authorizer.rest_cognito[0].id : (
    var.api_methods[count.index].authorization == "CUSTOM" ? aws_api_gateway_authorizer.rest_lambda[0].id : null
  )

  api_key_required = var.api_methods[count.index].api_key_required

  dynamic "request_parameters" {
    for_each = length(var.api_methods[count.index].request_parameters) > 0 ? var.api_methods[count.index].request_parameters : {}
    content {
      key   = request_parameters.key
      value = request_parameters.value
    }
  }
}

# API Gateway integrations
resource "aws_api_gateway_integration" "integration" {
  count = local.create_rest_api && length(var.api_integrations) > 0 ? length(var.api_integrations) : 0

  rest_api_id             = aws_api_gateway_rest_api.rest_api[0].id
  resource_id             = var.api_integrations[count.index].resource_id
  http_method             = var.api_integrations[count.index].http_method
  integration_http_method = var.api_integrations[count.index].integration_http_method
  type                    = var.api_integrations[count.index].type
  uri                     = var.api_integrations[count.index].uri

  connection_type      = var.api_integrations[count.index].connection_type
  connection_id        = var.api_integrations[count.index].connection_id
  timeout_milliseconds = var.api_integrations[count.index].timeout_milliseconds

  dynamic "request_parameters" {
    for_each = length(var.api_integrations[count.index].request_parameters) > 0 ? var.api_integrations[count.index].request_parameters : {}
    content {
      key   = request_parameters.key
      value = request_parameters.value
    }
  }

  dynamic "request_templates" {
    for_each = length(var.api_integrations[count.index].request_templates) > 0 ? var.api_integrations[count.index].request_templates : {}
    content {
      key   = request_templates.key
      value = request_templates.value
    }
  }
}

# Route53 Record for custom domain
resource "aws_route53_record" "api_domain" {
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

# CloudWatch Dashboard for API Gateway
resource "aws_cloudwatch_dashboard" "api_dashboard" {
  count = var.create_dashboard ? 1 : 0

  dashboard_name = "${local.name_prefix}-dashboard"

  dashboard_body = templatefile(
    "${path.module}/templates/dashboard.json.tpl",
    {
      api_name    = local.name_prefix
      region      = var.region
      environment = try(var.tags["Environment"], "default")
      stage_name  = var.stage_name
      api_type    = var.api_type
      api_stages  = [var.stage_name]
      rest_api_id = local.create_rest_api ? aws_api_gateway_rest_api.rest_api[0].id : ""
      http_api_id = local.create_http_api ? aws_apigatewayv2_api.http_api[0].id : ""
    }
  )
}