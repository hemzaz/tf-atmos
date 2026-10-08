# Mock-provider tests for lambda_config (Cloud Posse aws-cognito's trigger keys)
# and the invoke permission the component grants each trigger function. Run from
# the component directory with `terraform init -backend=false && terraform test`.

mock_provider "aws" {
  mock_resource "aws_cognito_user_pool" {
    defaults = {
      arn = "arn:aws:cognito-idp:us-east-2:123456789012:userpool/us-east-2_test"
    }
  }
}

variables {
  region      = "us-east-2"
  name_prefix = "fnx-ue2-prod"
  tags = {
    Environment = "ue2"
    Tenant      = "fnx"
    ManagedBy   = "Terraform"
  }
}

run "no_trigger_by_default" {
  command = plan

  assert {
    condition     = length(aws_cognito_user_pool.this[0].lambda_config) == 0 && length(aws_lambda_permission.cognito) == 0
    error_message = "Without lambda_config the pool must have no trigger and no invoke permission."
  }
}

run "user_migration_trigger_and_its_permission" {
  command = apply

  variables {
    lambda_config = {
      user_migration = "arn:aws:lambda:us-east-2:123456789012:function:ue2-cognito-user-migration"
      custom_message = ""
    }
  }

  assert {
    condition     = aws_cognito_user_pool.this[0].lambda_config[0].user_migration == "arn:aws:lambda:us-east-2:123456789012:function:ue2-cognito-user-migration"
    error_message = "The user_migration ARN must reach the pool's lambda_config."
  }

  assert {
    condition     = keys(aws_lambda_permission.cognito) == ["user_migration"]
    error_message = "Only the set trigger gets an invoke permission; \"\" is unset."
  }

  assert {
    condition = (
      aws_lambda_permission.cognito["user_migration"].principal == "cognito-idp.amazonaws.com"
      && aws_lambda_permission.cognito["user_migration"].source_arn == "arn:aws:cognito-idp:us-east-2:123456789012:userpool/us-east-2_test"
      && aws_lambda_permission.cognito["user_migration"].statement_id == "fnx-ue2-prod-user_migration"
    )
    error_message = "The permission must allow cognito-idp.amazonaws.com, scoped to this pool's ARN."
  }
}

run "a_non_lambda_arn_is_rejected" {
  command = plan

  variables {
    lambda_config = { user_migration = "arn:aws:sns:us-east-2:123456789012:topic" }
  }

  expect_failures = [var.lambda_config]
}

run "a_function_in_another_region_is_rejected" {
  command = plan

  variables {
    lambda_config = { user_migration = "arn:aws:lambda:us-east-1:123456789012:function:ue1-cognito-user-migration" }
  }

  expect_failures = [var.lambda_config]
}
