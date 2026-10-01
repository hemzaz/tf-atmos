# Mock-provider tests for REST response caching (cache_method_paths): no AWS
# credentials, no network. Run from the component directory with
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
  region           = "eu-west-2"
  api_name         = "main-api"
  api_type         = "REST"
  create_dashboard = false
  tags = {
    Environment = "test"
    Tenant      = "fnx"
    ManagedBy   = "Terraform"
  }

  authorizer_type        = "COGNITO_USER_POOLS"
  cognito_user_pool_arns = ["arn:aws:cognito-idp:eu-west-2:123456789012:userpool/eu-west-2_EXAMPLE"]

  api_resources = [
    { path_part = "products" },
    { path_part = "me" },
  ]

  api_methods = [
    { resource_path = "/", http_method = "GET" },
    { resource_path = "/products", http_method = "GET" },
    { resource_path = "/me", http_method = "GET", authorization = "COGNITO_USER_POOLS" },
  ]

  api_integrations = [
    { resource_path = "/", http_method = "GET", integration_http_method = "GET", type = "MOCK" },
    { resource_path = "/products", http_method = "GET", integration_http_method = "GET", type = "MOCK" },
    { resource_path = "/me", http_method = "GET", integration_http_method = "GET", type = "MOCK" },
  ]
}

run "nothing_is_cached_by_default" {
  command = plan

  assert {
    condition     = length(aws_api_gateway_method_settings.cache) == 0
    error_message = "No per-method cache settings by default."
  }

  assert {
    condition     = aws_api_gateway_method_settings.stage[0].method_path == "*/*" && aws_api_gateway_method_settings.stage[0].settings[0].caching_enabled == false
    error_message = "The stage-wide */* settings exist but do not cache."
  }

  assert {
    condition     = aws_api_gateway_stage.rest_stage[0].cache_cluster_enabled == false
    error_message = "No (billed) cache cluster by default."
  }
}

run "stage_wide_settings_apply_without_caching" {
  command = plan

  variables {
    throttling_burst_limit = 300
    throttling_rate_limit  = 500
  }

  assert {
    condition     = aws_api_gateway_method_settings.stage[0].settings[0].throttling_burst_limit == 300 && aws_api_gateway_method_settings.stage[0].settings[0].throttling_rate_limit == 500
    error_message = "throttling_* reach the stage even when nothing is cached."
  }

  assert {
    condition = (
      aws_api_gateway_method_settings.stage[0].settings[0].require_authorization_for_cache_control == true &&
      aws_api_gateway_method_settings.stage[0].settings[0].unauthorized_cache_control_header_strategy == "FAIL_WITH_403"
    )
    error_message = "Unauthorized Cache-Control bypass is refused with a 403 stage-wide."
  }
}

run "a_listed_public_get_is_cached_encrypted_and_guarded" {
  command = plan

  variables {
    enable_caching     = true
    cache_method_paths = ["GET /products", "GET /"]
    cache_ttl_seconds  = 120
  }

  assert {
    condition     = aws_api_gateway_stage.rest_stage[0].cache_cluster_enabled == true && aws_api_gateway_stage.rest_stage[0].cache_cluster_size == "0.5"
    error_message = "enable_caching provisions the 0.5 GB cache cluster."
  }

  assert {
    condition     = aws_api_gateway_method_settings.cache["GET /products"].method_path == "products/GET"
    error_message = "A resource path maps to API Gateway's <path without leading slash>/<method>."
  }

  assert {
    condition     = aws_api_gateway_method_settings.cache["GET /"].method_path == "~1/GET"
    error_message = "The root resource maps to ~1/<method>."
  }

  assert {
    condition = alltrue([
      for s in values(aws_api_gateway_method_settings.cache) :
      s.settings[0].caching_enabled == true &&
      s.settings[0].cache_data_encrypted == true &&
      s.settings[0].cache_ttl_in_seconds == 120 &&
      s.settings[0].require_authorization_for_cache_control == true &&
      s.settings[0].unauthorized_cache_control_header_strategy == "FAIL_WITH_403"
    ])
    error_message = "Every cached method is encrypted, uses the TTL, and refuses unauthorized Cache-Control with a 403."
  }

  assert {
    condition     = aws_api_gateway_method_settings.stage[0].settings[0].caching_enabled == false
    error_message = "Listing methods never turns on */* caching."
  }
}

run "cache_all_without_acknowledgment_is_rejected" {
  command = plan

  # Public methods only, so the acknowledgment is the only failing check.
  variables {
    enable_caching     = true
    cache_method_paths = ["*/*"]
    api_methods = [
      { resource_path = "/", http_method = "GET" },
    ]
    api_integrations = [
      { resource_path = "/", http_method = "GET", integration_http_method = "GET", type = "MOCK" },
    ]
  }

  expect_failures = [var.cache_method_paths]
}

run "cache_all_with_acknowledgment_caches_the_stage" {
  command = plan

  # The identity-keyed cache is still required for the authorized /me method.
  variables {
    enable_caching                 = true
    cache_method_paths             = ["*/*"]
    cache_all_methods_acknowledged = true
    api_methods = [
      { resource_path = "/", http_method = "GET" },
      { resource_path = "/products", http_method = "GET" },
      {
        resource_path      = "/me"
        http_method        = "GET"
        authorization      = "COGNITO_USER_POOLS"
        request_parameters = { "method.request.header.Authorization" = true }
      },
    ]
    api_integrations = [
      { resource_path = "/", http_method = "GET", integration_http_method = "GET", type = "MOCK" },
      { resource_path = "/products", http_method = "GET", integration_http_method = "GET", type = "MOCK" },
      {
        resource_path           = "/me"
        http_method             = "GET"
        integration_http_method = "GET"
        type                    = "MOCK"
        cache_key_parameters    = ["method.request.header.Authorization"]
      },
    ]
  }

  assert {
    condition     = aws_api_gateway_method_settings.stage[0].settings[0].caching_enabled == true && aws_api_gateway_method_settings.stage[0].settings[0].cache_data_encrypted == true
    error_message = "An acknowledged */* caches the whole stage, encrypted."
  }

  assert {
    condition     = length(aws_api_gateway_method_settings.cache) == 0
    error_message = "*/* is the stage-wide setting, not a per-method override."
  }

  assert {
    condition     = toset(aws_api_gateway_integration.integration["GET /me"].cache_key_parameters) == toset(["method.request.header.Authorization"])
    error_message = "cache_key_parameters reach the integration."
  }
}

run "caching_an_authorized_method_without_an_identity_cache_key_is_rejected" {
  command = plan

  variables {
    enable_caching     = true
    cache_method_paths = ["GET /me"]
  }

  expect_failures = [var.cache_method_paths]
}

run "caching_an_authorized_method_keyed_on_identity_is_accepted" {
  command = plan

  variables {
    enable_caching     = true
    cache_method_paths = ["GET /me"]
    api_methods = [
      { resource_path = "/", http_method = "GET" },
      { resource_path = "/products", http_method = "GET" },
      {
        resource_path      = "/me"
        http_method        = "GET"
        authorization      = "COGNITO_USER_POOLS"
        request_parameters = { "method.request.header.Authorization" = true }
      },
    ]
    api_integrations = [
      { resource_path = "/", http_method = "GET", integration_http_method = "GET", type = "MOCK" },
      { resource_path = "/products", http_method = "GET", integration_http_method = "GET", type = "MOCK" },
      {
        resource_path           = "/me"
        http_method             = "GET"
        integration_http_method = "GET"
        type                    = "MOCK"
        cache_key_parameters    = ["method.request.header.Authorization"]
      },
    ]
  }

  assert {
    condition     = aws_api_gateway_method_settings.cache["GET /me"].method_path == "me/GET"
    error_message = "The authorized method is cached once its cache is keyed on the caller."
  }
}

run "an_undeclared_cache_key_parameter_is_rejected" {
  command = plan

  variables {
    api_integrations = [
      { resource_path = "/", http_method = "GET", integration_http_method = "GET", type = "MOCK" },
      { resource_path = "/products", http_method = "GET", integration_http_method = "GET", type = "MOCK" },
      {
        resource_path           = "/me"
        http_method             = "GET"
        integration_http_method = "GET"
        type                    = "MOCK"
        cache_key_parameters    = ["method.request.header.Authorization"]
      },
    ]
  }

  expect_failures = [var.api_methods]
}

run "an_unknown_cache_method_path_is_rejected" {
  command = plan

  variables {
    enable_caching     = true
    cache_method_paths = ["GET /nope"]
  }

  expect_failures = [var.cache_method_paths]
}

run "caching_without_a_cache_cluster_is_rejected" {
  command = plan

  variables {
    cache_method_paths = ["GET /products"]
  }

  expect_failures = [var.cache_method_paths]
}

run "a_cache_cluster_with_nothing_to_cache_is_rejected" {
  command = plan

  variables {
    enable_caching = true
  }

  expect_failures = [var.cache_method_paths]
}
