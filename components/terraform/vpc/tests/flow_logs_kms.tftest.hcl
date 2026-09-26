# Mock-provider tests for flow_logs_kms_key_arn (F191-kms). No AWS
# credentials, no network. Run from the component directory with
# `terraform init -backend=false && terraform test`.

mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["eu-west-2a", "eu-west-2b", "eu-west-2c"]
    }
  }
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }
}

variables {
  region                  = "eu-west-2"
  ipv4_primary_cidr_block = "10.40.0.0/16"
  availability_zones      = ["eu-west-2a", "eu-west-2b"]
  private_subnets         = ["10.40.0.0/18", "10.40.64.0/18"]
  public_subnets          = ["10.40.192.0/22", "10.40.196.0/22"]
  tags = {
    Environment = "test"
    Tenant      = "fnx"
    ManagedBy   = "Terraform"
  }
}

run "own_key_by_default" {
  command = plan

  variables {
    vpc_flow_logs_enabled = true
  }

  # The key's arn is otherwise unknown at plan time; override_during = plan
  # makes it available so the log group's kms_key_id can be compared to it
  # without needing a full apply of the rest of the VPC.
  override_resource {
    target          = aws_kms_key.flow_logs[0]
    override_during = plan
    values = {
      arn = "arn:aws:kms:eu-west-2:123456789012:key/00000000-0000-0000-0000-000000000000"
    }
  }

  assert {
    condition     = length(aws_kms_key.flow_logs) == 1 && length(aws_kms_alias.flow_logs) == 1
    error_message = "With no flow_logs_kms_key_arn, the component creates and aliases its own key."
  }

  assert {
    condition     = aws_cloudwatch_log_group.flow_logs[0].kms_key_id == aws_kms_key.flow_logs[0].arn
    error_message = "The flow logs log group must use the component's own key by default."
  }
}

run "caller_key_encrypts_flow_logs_no_component_key_created" {
  command = plan

  variables {
    vpc_flow_logs_enabled = true
    flow_logs_kms_key_arn = "arn:aws:kms:eu-west-2:123456789012:key/11111111-2222-3333-4444-555555555555"
  }

  assert {
    condition     = length(aws_kms_key.flow_logs) == 0 && length(aws_kms_alias.flow_logs) == 0
    error_message = "With a caller key given, the component's own key (and its alias) must not be created: it would sit unused."
  }

  assert {
    condition     = aws_cloudwatch_log_group.flow_logs[0].kms_key_id == "arn:aws:kms:eu-west-2:123456789012:key/11111111-2222-3333-4444-555555555555"
    error_message = "With a caller key given, the flow logs log group must use it."
  }
}

run "caller_key_also_encrypts_the_s3_archive_bucket" {
  command = plan

  variables {
    vpc_flow_logs_enabled = true
    flow_logs_s3_backup   = true
    flow_logs_kms_key_arn = "arn:aws:kms:eu-west-2:123456789012:key/11111111-2222-3333-4444-555555555555"
  }

  assert {
    condition = one([
      for r in aws_s3_bucket_server_side_encryption_configuration.flow_logs[0].rule : r
    ]).apply_server_side_encryption_by_default[0].kms_master_key_id == "arn:aws:kms:eu-west-2:123456789012:key/11111111-2222-3333-4444-555555555555"
    error_message = "The flow logs S3 archive bucket must use the caller's key too, not the (uncreated) component key."
  }
}

run "flow_logs_kms_key_arn_rejects_a_malformed_arn" {
  command = plan

  variables {
    flow_logs_kms_key_arn = "not-an-arn"
  }

  expect_failures = [var.flow_logs_kms_key_arn]
}
