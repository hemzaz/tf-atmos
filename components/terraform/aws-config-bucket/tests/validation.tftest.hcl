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
  tenant              = "acme"
  # acme-audit is the mocked caller's account, so the account-verification mixin passes.
  account_map = {
    full_account_map = {
      acme-root     = "111111111111"
      acme-audit    = "123456789012"
      acme-security = "333333333333"
      acme-dev      = "444444444444"
      acme-prod     = "555555555555"
      acme-prod-eu  = "666666666666"
    }
  }
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

# A null key is refused by nullable = false before any validation runs ("required variable may
# not be set to null"), which expect_failures cannot capture, so it has no run here.
run "rejects_bad_partition" {
  command = plan

  variables {
    kms_master_key_arn = "arn:awsx:kms:us-east-1:123456789012:key/1234abcd-12ab-34cd-56ef-1234567890ab"
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

# Residency (E5a4b): the bucket policy denies config.amazonaws.com a put from an account outside the
# residency or under another key. The mocked json is not the policy, so the runs read the data
# source's statements, which are.
run "us_residency_derived_from_account_map" {
  command = plan

  # jsonencode on both sides: the statements are lists of objects, the expectations tuples.
  assert {
    condition = jsonencode([
      for s in data.aws_iam_policy_document.aws_config_bucket_policy[0].statement : [
        s.effect, sort(s.actions), [for c in s.condition : [c.test, c.variable, sort(c.values)]]
      ] if s.sid == "DenyDeliveryOutsideResidency"
      ]) == jsonencode([["Deny", ["s3:PutObject"], [["StringNotEquals", "aws:SourceAccount", [
        "111111111111", "123456789012", "333333333333", "444444444444", "555555555555"
    ]]]]])
    error_message = "DenyDeliveryOutsideResidency must deny every aws:SourceAccount but the account map's, prod-eu excluded."
  }

  assert {
    condition = jsonencode([
      for s in data.aws_iam_policy_document.aws_config_bucket_policy[0].statement : [
        s.effect, sort(s.actions), [for c in s.condition : [c.test, c.variable, sort(c.values)]]
      ] if s.sid == "DenyDeliveryUnderOtherKey"
      ]) == jsonencode([["Deny", ["s3:PutObject"], [["StringNotEqualsIfExists", "s3:x-amz-server-side-encryption-aws-kms-key-id", [
        "arn:aws:kms:us-east-1:123456789012:key/1234abcd-12ab-34cd-56ef-1234567890ab"
    ]]]]])
    error_message = "DenyDeliveryUnderOtherKey must deny a put naming any key but kms_master_key_arn."
  }

  assert {
    condition = [for s in data.aws_iam_policy_document.aws_config_bucket_policy[0].statement : s.sid] == [
      "AWSConfigBucketPermissionsCheck", "AWSConfigBucketExistenceCheck", "AWSConfigBucketDelivery",
      "AWSConfigRoleBucketChecks", "AWSConfigRoleDelivery",
      "DenyDeliveryOutsideResidency", "DenyDeliveryUnderOtherKey",
    ]
    error_message = "The policy is config-storage 1.0.2's three statements, the recorder role's two and the two residency Denys."
  }
}

run "eu_residency_explicit" {
  command = plan

  variables {
    region                = "eu-west-1"
    environment           = "ew1"
    residency_account_ids = ["666666666666", "111111111111", "123456789012", "333333333333"]
  }

  assert {
    condition = jsonencode([
      for s in data.aws_iam_policy_document.aws_config_bucket_policy[0].statement :
      [for c in s.condition : sort(c.values)] if s.sid == "DenyDeliveryOutsideResidency"
    ]) == jsonencode([[["111111111111", "123456789012", "333333333333", "666666666666"]]])
    error_message = "An explicit residency_account_ids is the residency."
  }
}

run "eu_residency_required" {
  command = plan

  variables {
    region      = "eu-west-1"
    environment = "ew1"
  }

  expect_failures = [data.aws_iam_policy_document.aws_config_bucket_policy]
}

run "rejects_empty_residency" {
  command = plan

  variables {
    residency_account_ids = []
  }

  expect_failures = [data.aws_iam_policy_document.aws_config_bucket_policy]
}

run "rejects_bad_residency_id" {
  command = plan

  variables {
    residency_account_ids = ["12345"]
  }

  expect_failures = [var.residency_account_ids]
}
