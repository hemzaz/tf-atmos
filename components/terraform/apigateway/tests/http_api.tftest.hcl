# Mock-provider tests for the HTTP API: no AWS credentials, no network. Run
# from the component directory with
# `terraform init -backend=false && terraform test`.

mock_provider "aws" {}

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

run "no_cors_and_no_vpc_link_by_default" {
  command = plan

  assert {
    condition     = length(aws_apigatewayv2_api.http_api[0].cors_configuration) == 0
    error_message = "cors_configuration defaults to null: no CORS."
  }

  assert {
    condition     = length(aws_apigatewayv2_vpc_link.http) == 0 && output.http_api_vpc_link_id == null
    error_message = "No VPC link without vpc_link_subnet_ids."
  }
}

run "cors_is_applied_when_set" {
  command = plan

  variables {
    cors_configuration = {
      allow_origins     = ["https://app.example.com"]
      allow_methods     = ["GET", "POST"]
      allow_headers     = ["Content-Type"]
      expose_headers    = ["X-Request-ID"]
      max_age           = 300
      allow_credentials = true
    }
  }

  assert {
    condition     = one(aws_apigatewayv2_api.http_api[0].cors_configuration).allow_origins == toset(["https://app.example.com"])
    error_message = "A stack's cors_configuration reaches the HTTP API."
  }

  assert {
    condition     = one(aws_apigatewayv2_api.http_api[0].cors_configuration).allow_credentials
    error_message = "allow_credentials is passed through."
  }
}

run "stage_carries_the_throttling_limits" {
  command = plan

  variables {
    throttling_burst_limit = 500
    throttling_rate_limit  = 1000
  }

  assert {
    condition     = one(aws_apigatewayv2_stage.http_stage[0].default_route_settings).throttling_burst_limit == 500
    error_message = "throttling_burst_limit reaches the HTTP stage."
  }

  assert {
    condition     = one(aws_apigatewayv2_stage.http_stage[0].default_route_settings).throttling_rate_limit == 1000
    error_message = "throttling_rate_limit reaches the HTTP stage."
  }
}

run "vpc_link_in_the_given_subnets" {
  command = plan

  variables {
    vpc_link_subnet_ids         = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
    vpc_link_security_group_ids = ["sg-0123456789abcdef0"]
  }

  assert {
    condition     = aws_apigatewayv2_vpc_link.http[0].name == "test-microservices-api-vpc-link"
    error_message = "The VPC link is <Environment>-<api_name>-vpc-link."
  }

  assert {
    condition     = aws_apigatewayv2_vpc_link.http[0].subnet_ids == toset(["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"])
    error_message = "The VPC link uses vpc_link_subnet_ids."
  }

  assert {
    condition     = aws_apigatewayv2_vpc_link.http[0].security_group_ids == toset(["sg-0123456789abcdef0"])
    error_message = "The VPC link uses vpc_link_security_group_ids."
  }
}

run "rest_api_creates_no_vpc_link" {
  command = plan

  variables {
    api_type                    = "REST"
    vpc_link_subnet_ids         = ["subnet-0123456789abcdef0"]
    vpc_link_security_group_ids = ["sg-0123456789abcdef0"]
  }

  assert {
    condition     = length(aws_apigatewayv2_vpc_link.http) == 0
    error_message = "The VPC link is for HTTP APIs only."
  }
}

run "rejects_a_vpc_link_without_security_groups" {
  command = plan

  variables {
    vpc_link_subnet_ids = ["subnet-0123456789abcdef0"]
  }

  expect_failures = [var.vpc_link_security_group_ids]
}

run "vpc_link_is_named_for_itself" {
  command = plan

  variables {
    vpc_link_subnet_ids         = ["subnet-0123456789abcdef0"]
    vpc_link_security_group_ids = ["sg-0123456789abcdef0"]
  }

  assert {
    condition     = aws_apigatewayv2_vpc_link.http[0].tags["Name"] == "test-microservices-api-vpc-link"
    error_message = "The VPC link's Name tag is <prefix>-vpc-link, not the API's name."
  }
}

run "disabled_creates_nothing" {
  command = plan

  variables {
    enabled                     = false
    vpc_link_subnet_ids         = ["subnet-0123456789abcdef0"]
    vpc_link_security_group_ids = ["sg-0123456789abcdef0"]
  }

  assert {
    condition     = length(aws_apigatewayv2_api.http_api) == 0 && length(aws_apigatewayv2_stage.http_stage) == 0 && length(aws_apigatewayv2_vpc_link.http) == 0
    error_message = "enabled = false creates no HTTP API, stage or VPC link."
  }

  assert {
    condition     = output.http_api_id == null && output.http_api_vpc_link_id == null && output.http_api_vpc_link_arn == null
    error_message = "Outputs are null when disabled."
  }
}

# Live staging and prod apigateway/main set cors_configuration on REST APIs.
# REST ignores it (CORS there is answered by OPTIONS methods); the plan must
# still succeed and create no HTTP resources.
run "rest_api_with_cors_set_plans_and_ignores_it" {
  command = plan

  variables {
    api_type = "REST"
    cors_configuration = {
      allow_origins     = ["*"]
      allow_methods     = ["GET"]
      allow_headers     = ["*"]
      expose_headers    = []
      max_age           = 300
      allow_credentials = false
    }
  }

  assert {
    condition     = length(aws_api_gateway_rest_api.rest_api) == 1 && length(aws_apigatewayv2_api.http_api) == 0
    error_message = "A REST API with cors_configuration set still plans, and no HTTP API is created."
  }
}

run "rejects_credentials_with_a_wildcard_origin" {
  command = plan

  variables {
    cors_configuration = {
      allow_origins     = ["*"]
      allow_methods     = ["GET"]
      allow_headers     = ["Content-Type"]
      expose_headers    = []
      max_age           = 300
      allow_credentials = true
    }
  }

  expect_failures = [var.cors_configuration]
}

run "rejects_max_age_over_a_day" {
  command = plan

  variables {
    cors_configuration = {
      allow_origins     = ["https://app.example.com"]
      allow_methods     = ["GET"]
      allow_headers     = ["Content-Type"]
      expose_headers    = []
      max_age           = 86401
      allow_credentials = false
    }
  }

  expect_failures = [var.cors_configuration]
}
