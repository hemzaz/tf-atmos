# Mock-provider tests for email_configuration (Cloud Posse aws-cognito's
# keys): no AWS credentials, no network. Run from the component directory
# with `terraform init -backend=false && terraform test`.

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

run "defaults_to_cognitos_own_sender" {
  command = plan

  assert {
    condition = (
      aws_cognito_user_pool.this[0].email_configuration[0].email_sending_account == "COGNITO_DEFAULT"
      && aws_cognito_user_pool.this[0].email_configuration[0].source_arn == null
    )
    error_message = "Without email_configuration the pool uses COGNITO_DEFAULT and no SES identity."
  }
}

run "developer_sends_through_the_ses_identity" {
  command = plan

  variables {
    email_configuration = {
      email_sending_account  = "DEVELOPER"
      source_arn             = "arn:aws:ses:us-east-1:123456789012:identity/example.com"
      from_email_address     = "App <no-reply@example.com>"
      reply_to_email_address = "support@example.com"
    }
  }

  assert {
    condition = (
      aws_cognito_user_pool.this[0].email_configuration[0].email_sending_account == "DEVELOPER"
      && aws_cognito_user_pool.this[0].email_configuration[0].source_arn == "arn:aws:ses:us-east-1:123456789012:identity/example.com"
      && aws_cognito_user_pool.this[0].email_configuration[0].from_email_address == "App <no-reply@example.com>"
      && aws_cognito_user_pool.this[0].email_configuration[0].reply_to_email_address == "support@example.com"
    )
    error_message = "Every email_configuration key reaches the pool."
  }
}

# A template passing optional settings through renders absent ones as "".
run "empty_strings_are_unset" {
  command = plan

  variables {
    email_configuration = {
      email_sending_account  = "COGNITO_DEFAULT"
      source_arn             = ""
      from_email_address     = ""
      reply_to_email_address = ""
    }
  }

  assert {
    condition = (
      aws_cognito_user_pool.this[0].email_configuration[0].source_arn == null
      && aws_cognito_user_pool.this[0].email_configuration[0].from_email_address == null
      && aws_cognito_user_pool.this[0].email_configuration[0].reply_to_email_address == null
    )
    error_message = "Empty strings reach the pool as unset."
  }
}

run "developer_with_an_empty_source_arn_is_rejected" {
  command = plan

  variables {
    email_configuration = { email_sending_account = "DEVELOPER", source_arn = "" }
  }

  expect_failures = [var.email_configuration]
}

run "developer_without_source_arn_is_rejected" {
  command = plan

  variables {
    email_configuration = { email_sending_account = "DEVELOPER" }
  }

  expect_failures = [var.email_configuration]
}

run "a_non_ses_source_arn_is_rejected" {
  command = plan

  variables {
    email_configuration = {
      email_sending_account = "DEVELOPER"
      source_arn            = "arn:aws:sns:us-east-1:123456789012:topic"
    }
  }

  expect_failures = [var.email_configuration]
}

run "from_address_without_developer_is_rejected" {
  command = plan

  variables {
    email_configuration = { from_email_address = "no-reply@example.com" }
  }

  expect_failures = [var.email_configuration]
}

run "an_unknown_sending_account_is_rejected" {
  command = plan

  variables {
    email_configuration = { email_sending_account = "SES" }
  }

  expect_failures = [var.email_configuration]
}
