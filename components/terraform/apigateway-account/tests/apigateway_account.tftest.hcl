# The real AWS provider is used, not a mock: aws_iam_policy_document is
# computed locally, and a mock would return a random string instead of the
# trust policy asserted below. It never reaches AWS: credentials are dummies
# and every check that would call AWS is skipped; every run is a plan.
# aws_partition is overridden in one run so the partition-aware ARN is asserted
# for a non-default partition too.
# Run: terraform init -backend=false && terraform test

provider "aws" {
  region                      = "eu-west-2"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
}

# The role ARN is computed by AWS; overriding it makes it known at plan, so the
# account setting's role ARN and the outputs can be compared. No run applies.
override_resource {
  target          = aws_iam_role.this
  override_during = plan
  values = {
    arn = "arn:aws:iam::123456789012:role/test-apigateway-cloudwatch-eu-west-2"
  }
}

variables {
  region = "eu-west-2"
  tags = {
    Environment = "test"
    Tenant      = "fnx"
    ManagedBy   = "Terraform"
  }
}

run "role_trusts_api_gateway_only" {
  command = plan

  assert {
    condition     = jsondecode(data.aws_iam_policy_document.assume.json).Statement[0].Principal.Service == "apigateway.amazonaws.com"
    error_message = "The role must be trusted by apigateway.amazonaws.com."
  }

  assert {
    condition     = jsondecode(data.aws_iam_policy_document.assume.json).Statement[0].Action == "sts:AssumeRole" && length(jsondecode(data.aws_iam_policy_document.assume.json).Statement) == 1
    error_message = "The trust policy is a single sts:AssumeRole statement."
  }

  assert {
    condition     = aws_iam_role.this[0].name == "test-apigateway-cloudwatch-eu-west-2"
    error_message = "The role is named <Environment>-apigateway-cloudwatch-<region>."
  }
}

run "attaches_the_managed_push_policy" {
  command = plan

  assert {
    condition     = aws_iam_role_policy_attachment.cloudwatch[0].policy_arn == "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
    error_message = "The role uses the AWS managed AmazonAPIGatewayPushToCloudWatchLogs policy."
  }

  assert {
    condition     = aws_iam_role_policy_attachment.cloudwatch[0].role == "test-apigateway-cloudwatch-eu-west-2"
    error_message = "The policy is attached to this component's role."
  }
}

run "policy_arn_follows_the_partition" {
  command = plan

  override_data {
    target = data.aws_partition.current
    values = {
      partition = "aws-us-gov"
    }
  }

  assert {
    condition     = aws_iam_role_policy_attachment.cloudwatch[0].policy_arn == "arn:aws-us-gov:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
    error_message = "The managed policy ARN must use the current partition."
  }
}

run "account_setting_uses_the_role" {
  command = plan

  assert {
    condition     = aws_api_gateway_account.this[0].cloudwatch_role_arn == aws_iam_role.this[0].arn
    error_message = "aws_api_gateway_account must point at this component's role."
  }

  assert {
    condition     = output.role_arn == "arn:aws:iam::123456789012:role/test-apigateway-cloudwatch-eu-west-2" && output.role_name == "test-apigateway-cloudwatch-eu-west-2"
    error_message = "role_arn and role_name outputs expose the role."
  }
}

run "disabled_creates_nothing" {
  command = plan

  variables {
    enabled = false
  }

  assert {
    condition     = length(aws_iam_role.this) == 0 && length(aws_iam_role_policy_attachment.cloudwatch) == 0 && length(aws_api_gateway_account.this) == 0
    error_message = "enabled = false must create no role, attachment or account setting."
  }

  assert {
    condition     = output.role_arn == null && output.role_name == null
    error_message = "Outputs are null when disabled."
  }
}

run "rejects_missing_environment_tag" {
  command = plan

  variables {
    tags = { Tenant = "fnx" }
  }

  expect_failures = [var.tags]
}
