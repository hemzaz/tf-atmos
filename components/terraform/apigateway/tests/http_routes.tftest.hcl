# Mock-provider tests for HTTP API routes (var.http_routes): no AWS
# credentials, no network. Run from the component directory with
# `terraform init -backend=false && terraform test`.

mock_provider "aws" {
  mock_resource "aws_apigatewayv2_authorizer" {
    override_during = plan
    defaults = {
      id = "authorizer-mock"
    }
  }
  mock_resource "aws_apigatewayv2_vpc_link" {
    override_during = plan
    defaults = {
      id = "vpcl-mock"
    }
  }
}

variables {
  region           = "eu-west-2"
  api_name         = "microservices-api"
  api_type         = "HTTP"
  create_dashboard = false
  tags = {
    Environment = "test"
    Tenant      = "fnx"
    ManagedBy   = "Terraform"
  }
}

run "no_routes_by_default" {
  command = plan

  assert {
    condition     = length(aws_apigatewayv2_route.http_route) == 0 && length(aws_apigatewayv2_integration.http_route) == 0
    error_message = "http_routes defaults to {}: no routes or integrations."
  }
}

run "http_proxy_over_vpc_link_wires_the_route_to_the_integration" {
  command = plan

  variables {
    http_routes = {
      "ANY /{proxy+}" = {
        integration_type = "HTTP_PROXY"
        connection_type  = "VPC_LINK"
        connection_id    = "vpcl-0123456789abcdef0"
        integration_uri  = "arn:aws:elasticloadbalancing:eu-west-2:123456789012:listener/app/microservices/abc/def"
      }
    }
  }

  assert {
    condition     = aws_apigatewayv2_integration.http_route["ANY /{proxy+}"].connection_type == "VPC_LINK"
    error_message = "connection_type reaches the integration."
  }

  assert {
    condition     = aws_apigatewayv2_integration.http_route["ANY /{proxy+}"].connection_id == "vpcl-0123456789abcdef0"
    error_message = "connection_id reaches the integration."
  }

  assert {
    condition     = aws_apigatewayv2_route.http_route["ANY /{proxy+}"].route_key == "ANY /{proxy+}"
    error_message = "route_key is the http_routes map key."
  }

  assert {
    condition     = aws_apigatewayv2_route.http_route["ANY /{proxy+}"].authorization_type == "NONE"
    error_message = "authorization_type defaults to NONE."
  }
}

run "connection_id_defaults_to_this_components_own_vpc_link" {
  command = plan

  variables {
    vpc_link_subnet_ids         = ["subnet-0123456789abcdef0"]
    vpc_link_security_group_ids = ["sg-0123456789abcdef0"]
    http_routes = {
      "ANY /{proxy+}" = {
        integration_type = "HTTP_PROXY"
        connection_type  = "VPC_LINK"
        integration_uri  = "arn:aws:elasticloadbalancing:eu-west-2:123456789012:listener/app/microservices/abc/def"
      }
    }
  }

  assert {
    condition     = aws_apigatewayv2_integration.http_route["ANY /{proxy+}"].connection_id == aws_apigatewayv2_vpc_link.http[0].id
    error_message = "A VPC_LINK route with no connection_id defaults to this component's own VPC link."
  }
}

run "jwt_route_uses_this_components_own_authorizer" {
  command = plan

  variables {
    authorizer_type            = "JWT"
    authorizer_identity_source = "$request.header.Authorization"
    jwt_audience               = ["client-id"]
    jwt_issuer                 = "https://cognito-idp.eu-west-2.amazonaws.com/eu-west-2_test"
    http_routes = {
      "ANY /{proxy+}" = {
        integration_type   = "HTTP_PROXY"
        connection_type    = "VPC_LINK"
        connection_id      = "vpcl-0123456789abcdef0"
        integration_uri    = "arn:aws:elasticloadbalancing:eu-west-2:123456789012:listener/app/microservices/abc/def"
        authorization_type = "JWT"
      }
    }
  }

  assert {
    condition     = aws_apigatewayv2_route.http_route["ANY /{proxy+}"].authorization_type == "JWT"
    error_message = "authorization_type reaches the route."
  }

  assert {
    condition     = aws_apigatewayv2_route.http_route["ANY /{proxy+}"].authorizer_id == aws_apigatewayv2_authorizer.http_jwt[0].id
    error_message = "A JWT route uses this component's own JWT authorizer."
  }
}

run "aws_proxy_route_grants_lambda_invoke_permission" {
  command = plan

  variables {
    http_routes = {
      "POST /webhook" = {
        integration_type     = "AWS_PROXY"
        integration_uri      = "arn:aws:lambda:eu-west-2:123456789012:function:webhook"
        lambda_function_name = "webhook"
      }
    }
  }

  assert {
    condition     = length(aws_lambda_permission.http_route_invoke) == 1
    error_message = "An AWS_PROXY route gets a matching aws_lambda_permission."
  }

  assert {
    condition     = aws_lambda_permission.http_route_invoke["POST /webhook"].function_name == "webhook"
    error_message = "lambda_function_name reaches the permission's function_name."
  }

  assert {
    condition     = aws_lambda_permission.http_route_invoke["POST /webhook"].principal == "apigateway.amazonaws.com"
    error_message = "Only API Gateway may invoke it."
  }
}

run "rejects_aws_proxy_without_lambda_function_name" {
  command = plan

  variables {
    http_routes = {
      "POST /webhook" = {
        integration_type = "AWS_PROXY"
        integration_uri  = "arn:aws:lambda:eu-west-2:123456789012:function:webhook"
      }
    }
  }

  expect_failures = [var.http_routes]
}

run "rejects_vpc_link_without_connection_id" {
  command = plan

  variables {
    http_routes = {
      "ANY /{proxy+}" = {
        integration_type = "HTTP_PROXY"
        connection_type  = "VPC_LINK"
        integration_uri  = "arn:aws:elasticloadbalancing:eu-west-2:123456789012:listener/app/microservices/abc/def"
      }
    }
  }

  expect_failures = [var.http_routes]
}

run "rejects_a_jwt_route_without_a_jwt_authorizer_on_the_component" {
  command = plan

  variables {
    http_routes = {
      "ANY /{proxy+}" = {
        integration_type   = "HTTP_PROXY"
        connection_type    = "VPC_LINK"
        connection_id      = "vpcl-0123456789abcdef0"
        integration_uri    = "arn:aws:elasticloadbalancing:eu-west-2:123456789012:listener/app/microservices/abc/def"
        authorization_type = "JWT"
      }
    }
  }

  expect_failures = [var.http_routes]
}

run "rest_api_ignores_http_routes" {
  command = plan

  variables {
    api_type = "REST"
    http_routes = {
      "ANY /{proxy+}" = {
        integration_type = "HTTP_PROXY"
        connection_type  = "VPC_LINK"
        connection_id    = "vpcl-0123456789abcdef0"
        integration_uri  = "arn:aws:elasticloadbalancing:eu-west-2:123456789012:listener/app/microservices/abc/def"
      }
    }
  }

  assert {
    condition     = length(aws_apigatewayv2_route.http_route) == 0 && length(aws_apigatewayv2_integration.http_route) == 0
    error_message = "A REST API creates no HTTP API routes or integrations, the same way it ignores cors_configuration."
  }
}
