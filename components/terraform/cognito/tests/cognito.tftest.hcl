# Mock-provider tests: no AWS credentials, no network. Run from the component
# directory with `terraform init -backend=false && terraform test`.
#
# Covers the feature plan (user_pool_tier) and its pairing with threat
# protection: AUDIT and ENFORCED are Plus-plan features
# (https://docs.aws.amazon.com/cognito/latest/developerguide/cognito-sign-in-feature-plans.html).

mock_provider "aws" {}

variables {
  region      = "us-east-1"
  name_prefix = "fnx-test-dev"
  tags = {
    Environment = "test"
    Tenant      = "fnx"
    ManagedBy   = "Terraform"
  }
}

run "defaults_are_essentials_without_threat_protection" {
  command = plan

  assert {
    condition = (
      aws_cognito_user_pool.this[0].user_pool_tier == "ESSENTIALS"
      && aws_cognito_user_pool.this[0].user_pool_add_ons[0].advanced_security_mode == "OFF"
    )
    error_message = "The component defaults must be consistent: ESSENTIALS with threat protection OFF."
  }
}

run "enforced_with_plus_is_accepted" {
  command = plan

  variables {
    advanced_security_mode = "ENFORCED"
    user_pool_tier         = "PLUS"
  }

  assert {
    condition = (
      aws_cognito_user_pool.this[0].user_pool_tier == "PLUS"
      && aws_cognito_user_pool.this[0].user_pool_add_ons[0].advanced_security_mode == "ENFORCED"
    )
    error_message = "ENFORCED with PLUS (what catalog/cognito/defaults.yaml sets) must reach the pool unchanged."
  }
}

run "enforced_without_plus_is_rejected" {
  command = plan

  variables {
    advanced_security_mode = "ENFORCED"
    user_pool_tier         = "ESSENTIALS"
  }

  expect_failures = [var.advanced_security_mode]
}

run "audit_without_plus_is_rejected" {
  command = plan

  variables {
    advanced_security_mode = "AUDIT"
    user_pool_tier         = "LITE"
  }

  expect_failures = [var.advanced_security_mode]
}

run "custom_string_attribute_reaches_the_schema" {
  command = plan

  variables {
    string_schemas = [{
      name                         = "tenant_id"
      string_attribute_constraints = { min_length = 1, max_length = 128 }
    }]
  }

  assert {
    condition = (
      length(aws_cognito_user_pool.this[0].schema) == 1
      && one(aws_cognito_user_pool.this[0].schema).name == "tenant_id"
      && one(aws_cognito_user_pool.this[0].schema).attribute_data_type == "String"
      && one(aws_cognito_user_pool.this[0].schema).mutable
      && one(one(aws_cognito_user_pool.this[0].schema).string_attribute_constraints).max_length == "128"
    )
    error_message = "A string_schemas entry is a String schema attribute with its constraints."
  }
}

run "custom_prefix_in_a_schema_name_is_rejected" {
  command = plan

  variables {
    string_schemas = [{ name = "custom:tenant_id" }]
  }

  expect_failures = [var.string_schemas]
}

run "resource_server_scopes_for_a_client_credentials_client" {
  command = plan

  variables {
    domain_prefix = "fnx-test-api"
    resource_servers = [{
      identifier = "fnx-test-api"
      name       = "API"
      scope = [
        { scope_name = "read", scope_description = "Read access" },
        { scope_name = "write", scope_description = "Write access" },
      ]
    }]
    clients = {
      api = {
        allowed_oauth_flows  = ["client_credentials"]
        allowed_oauth_scopes = ["fnx-test-api/read", "fnx-test-api/write"]
        explicit_auth_flows  = ["ALLOW_REFRESH_TOKEN_AUTH"]
      }
    }
  }

  assert {
    condition = (
      aws_cognito_resource_server.this["fnx-test-api"].name == "API"
      && length(aws_cognito_resource_server.this["fnx-test-api"].scope) == 2
    )
    error_message = "Each resource_servers entry is a resource server, keyed by identifier, with its scopes."
  }

  assert {
    condition = (
      aws_cognito_user_pool_client.this["api"].allowed_oauth_flows_user_pool_client
      && aws_cognito_user_pool_client.this["api"].generate_secret
    )
    error_message = "A client_credentials client is an OAuth client with a secret."
  }
}

run "duplicate_resource_server_identifiers_are_rejected" {
  command = plan

  variables {
    resource_servers = [
      { identifier = "api", name = "API" },
      { identifier = "api", name = "API again" },
    ]
  }

  expect_failures = [var.resource_servers]
}

run "unknown_tier_is_rejected" {
  command = plan

  variables {
    user_pool_tier = "ENTERPRISE"
  }

  expect_failures = [var.user_pool_tier]
}
