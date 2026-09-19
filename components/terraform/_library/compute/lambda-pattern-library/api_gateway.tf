# Lambda Pattern Library Module - API Gateway trigger (REST API pattern)
#
# Implemented inline (previously referenced a non-existent ./modules/api-gateway-lambda).
# REST (v1) and HTTP (v2) APIs both proxy every route to the function.
# AWS provider v6: the stage is managed by aws_api_gateway_stage; stage_name /
# invoke_url no longer exist on aws_api_gateway_deployment.

locals {
  create_rest_api = var.enable_api_gateway && var.api_gateway_type == "REST"
  create_http_api = var.enable_api_gateway && var.api_gateway_type == "HTTP"

  api_gateway_name = "${local.function_name}-api"

  # HTTP APIs use JWT authorizers instead of COGNITO_USER_POOLS.
  http_api_authorization = var.api_gateway_authorization == "COGNITO_USER_POOLS" ? "JWT" : var.api_gateway_authorization

  api_gateway_access_log_format = jsonencode({
    requestId      = "$context.requestId"
    ip             = "$context.identity.sourceIp"
    requestTime    = "$context.requestTime"
    httpMethod     = "$context.httpMethod"
    routeKey       = "$context.routeKey"
    status         = "$context.status"
    protocol       = "$context.protocol"
    responseLength = "$context.responseLength"
  })
}

resource "aws_cloudwatch_log_group" "api_gateway" {
  count = var.enable_api_gateway && var.enable_api_gateway_access_logs ? 1 : 0

  name              = "/aws/apigateway/${local.api_gateway_name}"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

# ------------------------------------------------------------------------------
# REST API (v1)
# ------------------------------------------------------------------------------

resource "aws_api_gateway_rest_api" "main" {
  count = local.create_rest_api ? 1 : 0

  name = local.api_gateway_name

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = local.common_tags
}

resource "aws_api_gateway_resource" "proxy" {
  count = local.create_rest_api ? 1 : 0

  rest_api_id = aws_api_gateway_rest_api.main[0].id
  parent_id   = aws_api_gateway_rest_api.main[0].root_resource_id
  path_part   = "{proxy+}"
}

# ANY on "/" and "/{proxy+}". CORS preflight (OPTIONS) is proxied to the function.
resource "aws_api_gateway_method" "main" {
  for_each = local.create_rest_api ? toset(["root", "proxy"]) : toset([])

  rest_api_id   = aws_api_gateway_rest_api.main[0].id
  resource_id   = each.key == "root" ? aws_api_gateway_rest_api.main[0].root_resource_id : aws_api_gateway_resource.proxy[0].id
  http_method   = "ANY"
  authorization = var.api_gateway_authorization
  authorizer_id = contains(["COGNITO_USER_POOLS", "CUSTOM"], var.api_gateway_authorization) ? var.api_gateway_authorizer_id : null
}

resource "aws_api_gateway_integration" "main" {
  for_each = aws_api_gateway_method.main

  rest_api_id             = each.value.rest_api_id
  resource_id             = each.value.resource_id
  http_method             = each.value.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.main.invoke_arn
}

resource "aws_api_gateway_deployment" "main" {
  count = local.create_rest_api ? 1 : 0

  rest_api_id = aws_api_gateway_rest_api.main[0].id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.proxy[0].id,
      [for m in aws_api_gateway_method.main : [m.id, m.authorization, m.authorizer_id]],
      [for i in aws_api_gateway_integration.main : [i.id, i.uri]],
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "main" {
  count = local.create_rest_api ? 1 : 0

  rest_api_id          = aws_api_gateway_rest_api.main[0].id
  deployment_id        = aws_api_gateway_deployment.main[0].id
  stage_name           = var.api_gateway_stage_name
  xray_tracing_enabled = var.enable_xray_tracing

  # Note: REST API access logging requires the account-level API Gateway
  # CloudWatch role (aws_api_gateway_account), which is managed outside this module.
  dynamic "access_log_settings" {
    for_each = var.enable_api_gateway_access_logs ? [1] : []
    content {
      destination_arn = aws_cloudwatch_log_group.api_gateway[0].arn
      format          = local.api_gateway_access_log_format
    }
  }

  tags = local.common_tags
}

resource "aws_api_gateway_method_settings" "main" {
  count = local.create_rest_api ? 1 : 0

  rest_api_id = aws_api_gateway_rest_api.main[0].id
  stage_name  = aws_api_gateway_stage.main[0].stage_name
  method_path = "*/*"

  settings {
    throttling_burst_limit = var.api_gateway_throttle_burst_limit
    throttling_rate_limit  = var.api_gateway_throttle_rate_limit
  }
}

# ------------------------------------------------------------------------------
# HTTP API (v2)
# ------------------------------------------------------------------------------

resource "aws_apigatewayv2_api" "main" {
  count = local.create_http_api ? 1 : 0

  name          = local.api_gateway_name
  protocol_type = "HTTP"

  dynamic "cors_configuration" {
    for_each = var.api_gateway_cors_enabled ? [1] : []
    content {
      allow_origins = var.api_gateway_cors_allow_origins
      allow_methods = ["*"]
      allow_headers = ["*"]
    }
  }

  tags = local.common_tags
}

resource "aws_apigatewayv2_integration" "main" {
  count = local.create_http_api ? 1 : 0

  api_id                 = aws_apigatewayv2_api.main[0].id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.main.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "main" {
  count = local.create_http_api ? 1 : 0

  api_id             = aws_apigatewayv2_api.main[0].id
  route_key          = "$default"
  target             = "integrations/${aws_apigatewayv2_integration.main[0].id}"
  authorization_type = local.http_api_authorization
  authorizer_id      = local.http_api_authorization == "NONE" || local.http_api_authorization == "AWS_IAM" ? null : var.api_gateway_authorizer_id
}

resource "aws_apigatewayv2_stage" "main" {
  count = local.create_http_api ? 1 : 0

  api_id      = aws_apigatewayv2_api.main[0].id
  name        = var.api_gateway_stage_name
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit = var.api_gateway_throttle_burst_limit
    throttling_rate_limit  = var.api_gateway_throttle_rate_limit
  }

  dynamic "access_log_settings" {
    for_each = var.enable_api_gateway_access_logs ? [1] : []
    content {
      destination_arn = aws_cloudwatch_log_group.api_gateway[0].arn
      format          = local.api_gateway_access_log_format
    }
  }

  tags = local.common_tags
}

# ------------------------------------------------------------------------------
# Invoke permission (both API types)
# ------------------------------------------------------------------------------

resource "aws_lambda_permission" "api_gateway" {
  count = var.enable_api_gateway ? 1 : 0

  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.main.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${local.create_rest_api ? aws_api_gateway_rest_api.main[0].execution_arn : aws_apigatewayv2_api.main[0].execution_arn}/*/*"
}
