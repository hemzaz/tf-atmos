# Mock-provider tests: no AWS credentials, no network. Run from the component
# directory with `terraform init -backend=false && terraform test`.

mock_provider "aws" {
  override_during = plan

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }
}

variables {
  region = "us-east-1"
  tags = {
    Environment = "test"
    Tenant      = "fnx"
    ManagedBy   = "Terraform"
  }
}

run "off_by_default_creates_nothing" {
  command = plan

  assert {
    condition     = length(aws_inspector2_enabler.main) == 0 && length(data.aws_caller_identity.current) == 0
    error_message = "enabled defaults to false: no enabler and no caller identity lookup."
  }

  assert {
    condition     = output.account_id == null && length(output.enabled_resource_types) == 0
    error_message = "Disabled: account_id is null (security-monitoring's Inspector route stays off) and no resource types."
  }
}

run "enabled_uses_cloud_posse_defaults" {
  command = plan

  variables {
    enabled = true
  }

  assert {
    condition     = aws_inspector2_enabler.main[0].account_ids == toset(["123456789012"])
    error_message = "The enabler covers this account only."
  }

  assert {
    condition     = output.enabled_resource_types == tolist(["EC2", "ECR", "LAMBDA"])
    error_message = "Cloud Posse defaults: EC2, ECR and LAMBDA on, LAMBDA_CODE off."
  }

  assert {
    condition     = output.account_id == "123456789012"
    error_message = "account_id is the enabled account."
  }
}

run "resource_types_follow_the_flags" {
  command = plan

  variables {
    enabled                 = true
    auto_enable_ec2         = false
    auto_enable_ecr         = true
    auto_enable_lambda      = true
    auto_enable_lambda_code = true
  }

  assert {
    condition     = aws_inspector2_enabler.main[0].resource_types == toset(["ECR", "LAMBDA", "LAMBDA_CODE"])
    error_message = "Only the flagged resource types are scanned, LAMBDA_CODE included."
  }
}

run "rejects_enabled_without_resource_types" {
  command = plan

  variables {
    enabled            = true
    auto_enable_ec2    = false
    auto_enable_ecr    = false
    auto_enable_lambda = false
  }

  expect_failures = [var.enabled]
}

run "rejects_lambda_code_without_lambda" {
  command = plan

  variables {
    enabled                 = true
    auto_enable_lambda      = false
    auto_enable_lambda_code = true
  }

  expect_failures = [var.auto_enable_lambda_code]
}

run "disabled_ignores_empty_resource_types" {
  command = plan

  variables {
    auto_enable_ec2    = false
    auto_enable_ecr    = false
    auto_enable_lambda = false
  }

  assert {
    condition     = length(aws_inspector2_enabler.main) == 0
    error_message = "With enabled false, no resource type is required."
  }
}
