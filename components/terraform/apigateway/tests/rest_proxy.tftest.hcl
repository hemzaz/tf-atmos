# Mock-provider tests for a REST {proxy+} catch-all behind a Cognito
# authorizer with OAuth scopes (the serverless-api template): no AWS
# credentials, no network. Run from the component directory with
# `terraform init -backend=false && terraform test`.

mock_provider "aws" {
  mock_resource "aws_api_gateway_rest_api" {
    override_during = plan
    defaults = {
      id               = "restapi-mock"
      root_resource_id = "root-mock"
      execution_arn    = "arn:aws:execute-api:us-east-1:123456789012:restapi-mock"
    }
  }
}

variables {
  region           = "us-east-1"
  api_name         = "serverless-api"
  api_type         = "REST"
  create_dashboard = false
  tags = {
    Environment = "test"
    Tenant      = "fnx"
    ManagedBy   = "Terraform"
  }

  authorizer_type        = "COGNITO_USER_POOLS"
  cognito_user_pool_arns = ["arn:aws:cognito-idp:us-east-1:123456789012:userpool/us-east-1_EXAMPLE"]

  api_resources = [{ path_part = "{proxy+}" }]

  api_methods = [
    { resource_path = "/", http_method = "ANY", authorization = "COGNITO_USER_POOLS", authorization_scopes = ["api/read", "api/write"] },
    { resource_path = "/{proxy+}", http_method = "ANY", authorization = "COGNITO_USER_POOLS", authorization_scopes = ["api/read", "api/write"] },
  ]

  api_integrations = [
    {
      resource_path           = "/"
      http_method             = "ANY"
      integration_http_method = "POST"
      type                    = "AWS_PROXY"
      uri                     = "arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:123456789012:function:test-api-handler/invocations"
      lambda_function_name    = "test-api-handler"
    },
    {
      resource_path           = "/{proxy+}"
      http_method             = "ANY"
      integration_http_method = "POST"
      type                    = "AWS_PROXY"
      uri                     = "arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:123456789012:function:test-api-handler/invocations"
      lambda_function_name    = "test-api-handler"
    },
  ]
}

# Regression: the REST statement_id only replaced " " and "/", so a
# "/{proxy+}" key failed Lambda's ^[a-zA-Z0-9_-]+$ at plan.
run "proxy_resource_gets_valid_distinct_statement_ids" {
  command = plan

  assert {
    condition = alltrue([
      for p in values(aws_lambda_permission.api_gateway_invoke) : can(regex("^[a-zA-Z0-9_-]+$", p.statement_id))
    ])
    error_message = "Every REST invoke permission's statement_id must only contain alphanumerics, underscores or dashes."
  }

  assert {
    condition     = aws_lambda_permission.api_gateway_invoke["ANY /"].statement_id != aws_lambda_permission.api_gateway_invoke["ANY /{proxy+}"].statement_id
    error_message = "Distinct methods must produce distinct statement_ids."
  }
}

run "cognito_method_carries_its_scopes" {
  command = plan

  assert {
    condition     = toset(aws_api_gateway_method.method["ANY /{proxy+}"].authorization_scopes) == toset(["api/read", "api/write"])
    error_message = "authorization_scopes reach the method."
  }
}

run "scopes_default_to_none" {
  command = plan

  variables {
    api_methods = [
      { resource_path = "/", http_method = "ANY", authorization = "COGNITO_USER_POOLS" },
      { resource_path = "/{proxy+}", http_method = "ANY", authorization = "COGNITO_USER_POOLS" },
    ]
  }

  assert {
    condition     = aws_api_gateway_method.method["ANY /"].authorization_scopes == null
    error_message = "Without authorization_scopes the method takes ID tokens (no scopes set)."
  }
}

run "rejects_scopes_on_a_non_cognito_method" {
  command = plan

  variables {
    api_methods = [
      { resource_path = "/", http_method = "ANY", authorization = "NONE", authorization_scopes = ["api/read"] },
      { resource_path = "/{proxy+}", http_method = "ANY", authorization = "COGNITO_USER_POOLS" },
    ]
  }

  expect_failures = [var.api_methods]
}
