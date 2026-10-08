# Mock-provider tests for flow_logs_kms_key_arn (F191-kms). No AWS
# credentials, no network. Run from the component directory with
# `terraform init -backend=false && terraform test`.

mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["us-east-1a", "us-east-1b", "us-east-1c"]
    }
  }
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }
}

variables {
  region                  = "us-east-1"
  ipv4_primary_cidr_block = "10.40.0.0/16"
  availability_zones      = ["us-east-1a", "us-east-1b"]
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
      arn = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000"
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
    flow_logs_kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"
  }

  assert {
    condition     = length(aws_kms_key.flow_logs) == 0 && length(aws_kms_alias.flow_logs) == 0
    error_message = "With a caller key given, the component's own key (and its alias) must not be created: it would sit unused."
  }

  assert {
    condition     = aws_cloudwatch_log_group.flow_logs[0].kms_key_id == "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"
    error_message = "With a caller key given, the flow logs log group must use it."
  }
}

run "caller_key_also_encrypts_the_s3_archive_bucket" {
  command = plan

  variables {
    vpc_flow_logs_enabled = true
    flow_logs_s3_backup   = true
    flow_logs_kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"
  }

  assert {
    condition = one([
      for r in aws_s3_bucket_server_side_encryption_configuration.flow_logs[0].rule : r
    ]).apply_server_side_encryption_by_default[0].kms_master_key_id == "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"
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

# S4: the flow-logs role trust carries AWS's documented confused-deputy
# conditions (vpc/latest/userguide/flow-logs-iam-role.html).
run "flow_logs_role_trust_is_scoped_to_this_account" {
  command = plan

  variables {
    vpc_flow_logs_enabled = true
    flow_logs_kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"
  }

  assert {
    condition = (
      jsondecode(aws_iam_role.flow_logs[0].assume_role_policy).Statement[0].Principal.Service == "vpc-flow-logs.amazonaws.com"
      && jsondecode(aws_iam_role.flow_logs[0].assume_role_policy).Statement[0].Condition.StringEquals["aws:SourceAccount"] == "123456789012"
      && jsondecode(aws_iam_role.flow_logs[0].assume_role_policy).Statement[0].Condition.ArnLike["aws:SourceArn"] == "arn:aws:ec2:us-east-1:123456789012:vpc-flow-log/*"
    )
    error_message = "The flow-logs role must trust vpc-flow-logs.amazonaws.com only with aws:SourceAccount = this account and aws:SourceArn = a flow log in this account and region."
  }
}

# Two vpc instances of one stack (vpc/main, vpc/services) share an account:
# every account- or region-unique flow-logs name carries the instance's name.
run "account_unique_names_carry_the_instance_name" {
  command = plan

  variables {
    name                  = "services"
    vpc_flow_logs_enabled = true
    flow_logs_s3_backup   = true
  }

  assert {
    condition = (
      aws_kms_alias.flow_logs[0].name == "alias/test-vpc-services-flow-logs" &&
      aws_iam_role.flow_logs[0].name == "test-vpc-services-flow-logs-role" &&
      aws_iam_role_policy.flow_logs[0].name == "test-vpc-services-flow-logs-policy" &&
      aws_s3_bucket.flow_logs[0].bucket == "test-vpc-services-flow-logs-123456789012" &&
      aws_cloudwatch_metric_alarm.ssh_access[0].alarm_name == "test-vpc-services-high-ssh-access-attempts" &&
      aws_cloudwatch_metric_alarm.ssh_access[0].namespace == "VPC/FlowLogs/test-vpc-services" &&
      aws_cloudwatch_log_metric_filter.ssh_access[0].metric_transformation[0].namespace == "VPC/FlowLogs/test-vpc-services"
    )
    error_message = "The KMS alias, IAM role and policy, archive bucket, alarms and metric namespace are <Environment>-vpc-<name>-..."
  }

  assert {
    condition = (
      aws_vpc.main.tags["Name"] == "test-vpc-services" &&
      aws_subnet.private["10.40.0.0/18"].tags["Name"] == "test-vpc-services-private-subnet-1" &&
      aws_subnet.public["10.40.196.0/22"].tags["Name"] == "test-vpc-services-public-subnet-2" &&
      aws_internet_gateway.main.tags["Name"] == "test-vpc-services-igw"
    )
    error_message = "The VPC, subnet and internet gateway Name tags carry the instance's name: <Environment>-vpc-<name>[-...]."
  }
}

# The default name keeps the pre-name names: <Environment>-vpc-flow-logs-...
# and <Environment>-vpc, -igw, -private-subnet-N.
run "default_name_keeps_the_vpc_names" {
  command = plan

  variables {
    vpc_flow_logs_enabled = true
    flow_logs_s3_backup   = true
  }

  assert {
    condition = (
      aws_iam_role.flow_logs[0].name == "test-vpc-flow-logs-role" &&
      aws_s3_bucket.flow_logs[0].bucket == "test-vpc-flow-logs-123456789012" &&
      aws_cloudwatch_metric_alarm.ssh_access[0].alarm_name == "test-vpc-high-ssh-access-attempts" &&
      aws_vpc.main.tags["Name"] == "test-vpc" &&
      aws_subnet.private["10.40.0.0/18"].tags["Name"] == "test-private-subnet-1" &&
      aws_internet_gateway.main.tags["Name"] == "test-igw"
    )
    error_message = "name = \"vpc\" builds <Environment>-vpc-flow-logs-... and the <Environment>-<resource> Name tags."
  }
}

run "name_must_fit_a_bucket_name" {
  command = plan

  variables {
    name = "Services_1"
  }

  expect_failures = [var.name]
}

# The archive bucket <Environment>-vpc-<name>-flow-logs-<account id> is the
# longest built name: <Environment>-vpc-<name> may be 40 characters (63 for S3).
run "longest_name_fits_the_bucket_and_role" {
  command = plan

  variables {
    name                  = "abcdefghijklmnopqrstuvwxyz-abcd" # test-vpc- + 31 = 40
    vpc_flow_logs_enabled = true
    flow_logs_s3_backup   = true
  }

  assert {
    condition     = length(aws_s3_bucket.flow_logs[0].bucket) == 63 && length(aws_iam_role.flow_logs[0].name) <= 64
    error_message = "A 40-character <Environment>-vpc-<name> builds a 63-character archive bucket name."
  }
}

run "name_too_long_for_the_bucket" {
  command = plan

  variables {
    name = "abcdefghijklmnopqrstuvwxyz-abcde" # test-vpc- + 32 = 41
  }

  expect_failures = [var.name]
}

run "lane_environment_counts_toward_the_limit" {
  command = plan

  variables {
    name = "services"
    tags = {
      Environment = "ue1-a-very-long-lane-name-here" # + -vpc-services = 43
    }
  }

  expect_failures = [var.name]
}
