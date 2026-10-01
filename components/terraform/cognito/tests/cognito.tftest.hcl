# Mock-provider tests: no AWS credentials, no network. Run from the component
# directory with `terraform init -backend=false && terraform test`.
#
# Covers the feature plan (user_pool_tier) and its pairing with threat
# protection: AUDIT and ENFORCED are Plus-plan features
# (https://docs.aws.amazon.com/cognito/latest/developerguide/cognito-sign-in-feature-plans.html).

mock_provider "aws" {}

variables {
  region      = "eu-west-2"
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

run "unknown_tier_is_rejected" {
  command = plan

  variables {
    user_pool_tier = "ENTERPRISE"
  }

  expect_failures = [var.user_pool_tier]
}
