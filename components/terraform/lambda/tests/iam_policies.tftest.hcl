# Offline tests for iam_policies, set up as lambda.tftest.hcl (real AWS
# provider, dummy credentials, plan only; nothing reaches AWS).
# Run: terraform init -backend=false && terraform test

provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
}

variables {
  region        = "us-east-1"
  function_name = "orders"
  handler       = "index.handler"
  s3_bucket     = "test-artifacts"
  s3_key        = "orders/1.0.0.zip"
  tags = {
    Environment = "test"
    ManagedBy   = "Terraform"
  }
}

run "no_statements_no_policy" {
  command = plan

  assert {
    condition     = length(aws_iam_role_policy.lambda_iam_policies) == 0
    error_message = "The default (empty) iam_policies creates no inline policy."
  }
}

run "statements_rendered" {
  command = plan

  variables {
    iam_policies = [
      {
        sid       = "ReadLookupTable"
        actions   = ["dynamodb:GetItem", "dynamodb:Query"]
        resources = ["arn:aws:dynamodb:us-east-1:123456789012:table/test-lookup"]
      },
      {
        actions   = ["kms:Decrypt"]
        resources = ["arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"]
        conditions = [
          { test = "StringEquals", variable = "kms:ViaService", values = ["dynamodb.us-east-1.amazonaws.com"] },
        ]
      },
    ]
  }

  assert {
    condition     = aws_iam_role_policy.lambda_iam_policies[0].name == "test-orders-iam-policies"
    error_message = "The inline policy is <Environment>-<function_name>-iam-policies."
  }

  assert {
    condition = jsondecode(aws_iam_role_policy.lambda_iam_policies[0].policy).Statement == [
      {
        Sid      = "ReadLookupTable"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:Query"]
        Resource = ["arn:aws:dynamodb:us-east-1:123456789012:table/test-lookup"]
      },
      {
        Effect    = "Allow"
        Action    = ["kms:Decrypt"]
        Resource  = ["arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"]
        Condition = { StringEquals = { "kms:ViaService" = ["dynamodb.us-east-1.amazonaws.com"] } }
      },
    ]
    error_message = "Statements render with their Sid only when set, and conditions grouped by test and key."
  }
}

run "rejects_allow_star_action" {
  command = plan

  variables {
    iam_policies = [{ actions = ["*"], resources = ["*"] }]
  }

  expect_failures = [var.iam_policies]
}

run "rejects_empty_resources" {
  command = plan

  variables {
    iam_policies = [{ actions = ["s3:GetObject"], resources = [] }]
  }

  expect_failures = [var.iam_policies]
}
