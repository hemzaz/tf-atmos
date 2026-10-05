# Mock-provider tests for a REST {proxy+} catch-all behind a Cognito
# authorizer with OAuth scopes and an unauthenticated CORS preflight (the
# serverless-api template): no AWS credentials, no network. Run from the
# component directory with `terraform init -backend=false && terraform test`.

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

  # Reads take either scope, writes the write scope; the preflight is open.
  api_methods = [
    { resource_path = "/", http_method = "GET", authorization = "COGNITO_USER_POOLS", authorization_scopes = ["api/read", "api/write"] },
    { resource_path = "/", http_method = "POST", authorization = "COGNITO_USER_POOLS", authorization_scopes = ["api/write"] },
    { resource_path = "/", http_method = "OPTIONS", authorization = "NONE" },
    { resource_path = "/{proxy+}", http_method = "GET", authorization = "COGNITO_USER_POOLS", authorization_scopes = ["api/read", "api/write"] },
    { resource_path = "/{proxy+}", http_method = "POST", authorization = "COGNITO_USER_POOLS", authorization_scopes = ["api/write"] },
    { resource_path = "/{proxy+}", http_method = "OPTIONS", authorization = "NONE" },
  ]

  api_integrations = [
    for k in ["GET /", "POST /", "OPTIONS /", "GET /{proxy+}", "POST /{proxy+}", "OPTIONS /{proxy+}"] : {
      resource_path           = split(" ", k)[1]
      http_method             = split(" ", k)[0]
      integration_http_method = "POST"
      type                    = "AWS_PROXY"
      uri                     = "arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:123456789012:function:test-api-handler/invocations"
      lambda_function_name    = "test-api-handler"
    }
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
    condition     = length(distinct([for p in values(aws_lambda_permission.api_gateway_invoke) : p.statement_id])) == 6
    error_message = "Distinct methods must produce distinct statement_ids."
  }
}

# Two APIs granting one function the same method and path must not write the
# same statement_id into its policy: the API's name is part of the hash.
run "statement_id_includes_the_api_name" {
  command = plan

  assert {
    condition     = aws_lambda_permission.api_gateway_invoke["GET /"].statement_id == "AllowInvokeFrom-${substr(sha1("test-serverless-api|GET /"), 0, 16)}"
    error_message = "statement_id hashes <Environment>-<api_name>|<key>."
  }
}

run "statement_id_differs_for_another_api" {
  command = plan

  variables {
    api_name = "other-api"
  }

  assert {
    condition     = aws_lambda_permission.api_gateway_invoke["GET /"].statement_id != "AllowInvokeFrom-${substr(sha1("test-serverless-api|GET /"), 0, 16)}"
    error_message = "Another API's statement_id for the same method and path differs."
  }
}

run "cognito_methods_carry_their_scopes" {
  command = plan

  assert {
    condition     = toset(aws_api_gateway_method.method["GET /{proxy+}"].authorization_scopes) == toset(["api/read", "api/write"])
    error_message = "A read method takes either scope."
  }

  assert {
    condition     = toset(aws_api_gateway_method.method["POST /{proxy+}"].authorization_scopes) == toset(["api/write"])
    error_message = "A write method takes the write scope only."
  }
}

# A browser's CORS preflight carries no Authorization header: an OPTIONS
# method behind the authorizer (or an ANY that covers OPTIONS) answers 401.
run "preflight_is_unauthenticated" {
  command = plan

  assert {
    condition = alltrue([
      for k in ["OPTIONS /", "OPTIONS /{proxy+}"] :
      aws_api_gateway_method.method[k].authorization == "NONE" && aws_api_gateway_method.method[k].authorization_scopes == null
    ])
    error_message = "OPTIONS methods have authorization NONE and no scopes."
  }
}

run "scopes_default_to_none" {
  command = plan

  variables {
    api_methods = [
      { resource_path = "/", http_method = "GET", authorization = "COGNITO_USER_POOLS" },
      { resource_path = "/", http_method = "POST", authorization = "COGNITO_USER_POOLS" },
      { resource_path = "/", http_method = "OPTIONS" },
      { resource_path = "/{proxy+}", http_method = "GET", authorization = "COGNITO_USER_POOLS" },
      { resource_path = "/{proxy+}", http_method = "POST", authorization = "COGNITO_USER_POOLS" },
      { resource_path = "/{proxy+}", http_method = "OPTIONS" },
    ]
  }

  assert {
    condition     = aws_api_gateway_method.method["GET /"].authorization_scopes == null
    error_message = "Without authorization_scopes the method takes ID tokens (no scopes set)."
  }
}

run "rejects_scopes_on_a_non_cognito_method" {
  command = plan

  variables {
    api_methods = [
      { resource_path = "/", http_method = "GET", authorization = "COGNITO_USER_POOLS" },
      { resource_path = "/", http_method = "POST", authorization = "COGNITO_USER_POOLS" },
      { resource_path = "/", http_method = "OPTIONS", authorization = "NONE", authorization_scopes = ["api/read"] },
      { resource_path = "/{proxy+}", http_method = "GET", authorization = "COGNITO_USER_POOLS" },
      { resource_path = "/{proxy+}", http_method = "POST", authorization = "COGNITO_USER_POOLS" },
      { resource_path = "/{proxy+}", http_method = "OPTIONS" },
    ]
  }

  expect_failures = [var.api_methods]
}
