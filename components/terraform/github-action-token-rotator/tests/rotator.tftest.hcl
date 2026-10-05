# Mock-provider tests: no AWS credentials, no network. Run from the component
# directory with `terraform init -backend=false && terraform test`. The
# function's own logic is tested with `node --test functions/token-rotator/`.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
}

variables {
  region                           = "us-east-1"
  github_app_id                    = "123456"
  github_app_installation_id       = "7654321"
  github_org_name                  = "hemzaz"
  github_repository_name           = "tf-atmos"
  parameter_store_private_key_path = "/github/runners/app-private-key"
  parameter_store_token_path       = "/github/runners/registration-token"
  kms_key_arn                      = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
  tags = {
    Environment = "test"
    Tenant      = "fnx"
    ManagedBy   = "Terraform"
  }
}

run "token_parameter_is_a_kms_securestring_the_function_owns" {
  command = plan

  assert {
    condition = (
      aws_ssm_parameter.token[0].type == "SecureString"
      && aws_ssm_parameter.token[0].key_id == var.kms_key_arn
      && aws_ssm_parameter.token[0].name == "/github/runners/registration-token"
    )
    error_message = "The token is a SecureString on the given key, at parameter_store_token_path."
  }
}

run "function_carries_no_secret_and_targets_the_repository" {
  command = plan

  assert {
    condition = (
      aws_lambda_function.function[0].runtime == "nodejs22.x"
      && aws_lambda_function.function[0].environment[0].variables["GITHUB_SCOPE"] == "hemzaz/tf-atmos"
      && aws_lambda_function.function[0].environment[0].variables["PRIVATE_KEY_PARAMETER"] == "/github/runners/app-private-key"
      && aws_lambda_function.function[0].kms_key_arn == var.kms_key_arn
      && aws_lambda_function.function[0].reserved_concurrent_executions == 1
    )
    error_message = "The function gets the scope and parameter names, never the key itself."
  }

  assert {
    condition     = !anytrue([for v in values(aws_lambda_function.function[0].environment[0].variables) : strcontains(v, "PRIVATE KEY")])
    error_message = "No environment variable holds key material."
  }
}

run "organization_scope_without_a_repository" {
  command = plan

  variables {
    github_repository_name = null
  }

  assert {
    condition     = aws_lambda_function.function[0].environment[0].variables["GITHUB_SCOPE"] == "hemzaz"
    error_message = "Without a repository the runners register to the organization."
  }
}

run "rotates_every_30_minutes_by_default" {
  command = plan

  assert {
    condition     = aws_cloudwatch_event_rule.schedule[0].schedule_expression == "rate(30 minutes)"
    error_message = "A registration token lasts an hour; the default schedule renews it twice in that time."
  }

  assert {
    condition     = aws_lambda_permission.schedule[0].principal == "events.amazonaws.com"
    error_message = "EventBridge may invoke the function."
  }
}

run "log_group_is_encrypted" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_group.function[0].kms_key_id == var.kms_key_arn && aws_cloudwatch_log_group.function[0].name == "/aws/lambda/test-github-token-rotator"
    error_message = "The function's log group is <Environment>-github-token-rotator, on the key."
  }
}

run "disabled_creates_nothing" {
  command = plan

  variables {
    enabled = false
  }

  assert {
    condition     = length(aws_lambda_function.function) == 0 && length(aws_ssm_parameter.token) == 0
    error_message = "enabled = false creates nothing."
  }
}

run "rejects_a_relative_parameter_path" {
  command = plan

  variables {
    parameter_store_token_path = "github/runners/registration-token"
  }

  expect_failures = [var.parameter_store_token_path]
}

run "rejects_a_non_numeric_app_id" {
  command = plan

  variables {
    github_app_id = "my-app"
  }

  expect_failures = [var.github_app_id]
}

run "rejects_an_hourly_schedule_written_as_text" {
  command = plan

  variables {
    schedule_expression = "every 30 minutes"
  }

  expect_failures = [var.schedule_expression]
}
