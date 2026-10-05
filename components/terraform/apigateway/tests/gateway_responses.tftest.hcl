# Mock-provider tests for REST gateway responses (var.gateway_responses): no
# AWS credentials, no network. Run from the component directory with
# `terraform init -backend=false && terraform test`.

mock_provider "aws" {
  mock_resource "aws_api_gateway_rest_api" {
    override_during = plan
    defaults = {
      id               = "restapi-mock"
      root_resource_id = "root-mock"
    }
  }
}

variables {
  region           = "us-east-1"
  api_name         = "main-api"
  api_type         = "REST"
  create_dashboard = false
  tags = {
    Environment = "test"
    Tenant      = "fnx"
    ManagedBy   = "Terraform"
  }

  api_methods      = [{ resource_path = "/", http_method = "GET" }]
  api_integrations = [{ resource_path = "/", http_method = "GET", integration_http_method = "GET", type = "MOCK" }]
}

run "no_gateway_responses_by_default" {
  command = plan

  assert {
    condition     = length(aws_api_gateway_gateway_response.this) == 0
    error_message = "No gateway responses unless set."
  }
}

run "cors_headers_on_default_4xx_and_5xx" {
  command = plan

  variables {
    gateway_responses = {
      DEFAULT_4XX = {
        response_parameters = {
          "gatewayresponse.header.Access-Control-Allow-Origin"  = "'https://app.example.com'"
          "gatewayresponse.header.Access-Control-Allow-Headers" = "'Authorization,Content-Type'"
        }
      }
      DEFAULT_5XX = {
        response_parameters = {
          "gatewayresponse.header.Access-Control-Allow-Origin" = "'https://app.example.com'"
        }
      }
      UNAUTHORIZED = {
        status_code        = "401"
        response_templates = { "application/json" = "{\"message\":$context.error.messageString}" }
      }
    }
  }

  assert {
    condition     = length(aws_api_gateway_gateway_response.this) == 3
    error_message = "One gateway response per key."
  }

  assert {
    condition = (
      aws_api_gateway_gateway_response.this["DEFAULT_4XX"].response_type == "DEFAULT_4XX"
      && aws_api_gateway_gateway_response.this["DEFAULT_4XX"].response_parameters["gatewayresponse.header.Access-Control-Allow-Origin"] == "'https://app.example.com'"
      && aws_api_gateway_gateway_response.this["DEFAULT_4XX"].status_code == null
    )
    error_message = "DEFAULT_4XX carries its headers and keeps the type's default status."
  }

  assert {
    condition = (
      aws_api_gateway_gateway_response.this["UNAUTHORIZED"].status_code == "401"
      && aws_api_gateway_gateway_response.this["UNAUTHORIZED"].response_parameters == null
      && length(aws_api_gateway_gateway_response.this["UNAUTHORIZED"].response_templates) == 1
    )
    error_message = "status_code and response_templates reach the response."
  }
}

run "rejects_an_unknown_response_type" {
  command = plan

  variables {
    gateway_responses = { DEFAULT_4xx = {} }
  }

  expect_failures = [var.gateway_responses]
}

run "rejects_a_bad_status_code" {
  command = plan

  variables {
    gateway_responses = { DEFAULT_4XX = { status_code = "4xx" } }
  }

  expect_failures = [var.gateway_responses]
}

run "rejects_a_non_header_response_parameter" {
  command = plan

  variables {
    gateway_responses = {
      DEFAULT_4XX = { response_parameters = { "method.response.header.X-Foo" = "'bar'" } }
    }
  }

  expect_failures = [var.gateway_responses]
}

run "rejects_gateway_responses_on_an_http_api" {
  command = plan

  variables {
    api_type          = "HTTP"
    api_methods       = []
    api_integrations  = []
    gateway_responses = { DEFAULT_4XX = {} }
  }

  expect_failures = [var.gateway_responses]
}
