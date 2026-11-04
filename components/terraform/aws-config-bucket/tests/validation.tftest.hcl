# Mock-provider tests for the house key input (owner 2026-11-04): no AWS credentials, no
# network. Run from the component directory with
# `terraform init -backend=false && terraform test`.
#
# kms_master_key_arn is required and must be a customer managed key ARN: an alias ARN (including
# the AWS managed alias/aws/s3) or an empty value fails the plan.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  region              = "us-east-1"
  account_map_enabled = false
  namespace           = "fnx"
  environment         = "ue1"
  stage               = "audit"
  name                = "config"
  kms_master_key_arn  = "arn:aws:kms:us-east-1:123456789012:key/1234abcd-12ab-34cd-56ef-1234567890ab"
}

# A key ARN plans. (A test cannot read the nested module's encryption resource; trivy's AWS-0132
# in the security-scan gate proves the bucket is SSE-KMS with this input.)
run "accepts_key_arn" {
  command = plan
}

run "rejects_alias_arn" {
  command = plan

  variables {
    kms_master_key_arn = "arn:aws:kms:us-east-1:123456789012:alias/config-bucket"
  }

  expect_failures = [var.kms_master_key_arn]
}

run "rejects_aws_managed_alias" {
  command = plan

  variables {
    kms_master_key_arn = "arn:aws:kms:us-east-1:123456789012:alias/aws/s3"
  }

  expect_failures = [var.kms_master_key_arn]
}

run "rejects_empty" {
  command = plan

  variables {
    kms_master_key_arn = ""
  }

  expect_failures = [var.kms_master_key_arn]
}
