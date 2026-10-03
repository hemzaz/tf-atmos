# Mock-provider tests for flow_logs_s3_backup: the archive bucket gets its own
# flow log and a delivery bucket policy. No AWS credentials, no network.

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
  # The mock would otherwise return a random string, not JSON.
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  region                  = "us-east-1"
  ipv4_primary_cidr_block = "10.40.0.0/16"
  availability_zones      = ["us-east-1a", "us-east-1b"]
  private_subnets         = ["10.40.0.0/18", "10.40.64.0/18"]
  public_subnets          = ["10.40.192.0/22", "10.40.196.0/22"]
  vpc_flow_logs_enabled   = true
  tags = {
    Environment = "test"
    Tenant      = "fnx"
    ManagedBy   = "Terraform"
  }
}

run "s3_backup_off_one_flow_log" {
  command = plan

  assert {
    condition     = length(aws_flow_log.main) == 1 && length(aws_flow_log.s3) == 0
    error_message = "Without flow_logs_s3_backup there is only the CloudWatch flow log."
  }

  assert {
    condition     = length(aws_s3_bucket.flow_logs) == 0 && length(aws_s3_bucket_policy.flow_logs) == 0
    error_message = "Without flow_logs_s3_backup there is no archive bucket or bucket policy."
  }

  assert {
    condition     = length(jsondecode(aws_kms_key.flow_logs[0].policy).Statement) == 2
    error_message = "Without flow_logs_s3_backup the component key grants no log delivery statement."
  }
}

run "s3_backup_on_two_flow_logs" {
  command = plan

  variables {
    flow_logs_s3_backup        = true
    vpc_flow_logs_traffic_type = "REJECT"
  }

  override_resource {
    target          = aws_s3_bucket.flow_logs[0]
    override_during = plan
    values = {
      arn = "arn:aws:s3:::test-vpc-flow-logs-123456789012"
    }
  }

  assert {
    condition     = length(aws_flow_log.main) == 1 && length(aws_flow_log.s3) == 1
    error_message = "With flow_logs_s3_backup there are two flow logs: CloudWatch and S3."
  }

  assert {
    condition = (
      aws_flow_log.s3[0].log_destination_type == "s3"
      && aws_flow_log.s3[0].log_destination == "arn:aws:s3:::test-vpc-flow-logs-123456789012"
      && aws_flow_log.s3[0].traffic_type == "REJECT"
      && aws_flow_log.s3[0].iam_role_arn == null
    )
    error_message = "The S3 flow log must deliver the same traffic type into the archive bucket, with no IAM role."
  }

  assert {
    condition     = length(aws_s3_bucket_policy.flow_logs) == 1
    error_message = "With flow_logs_s3_backup the archive bucket gets the log delivery policy."
  }

  assert {
    condition = anytrue([
      for st in jsondecode(aws_kms_key.flow_logs[0].policy).Statement :
      st.Principal == { Service = "delivery.logs.amazonaws.com" } && st.Action == "kms:GenerateDataKey*"
      && st.Condition.StringEquals["aws:SourceAccount"] == "123456789012"
      && st.Condition.ArnLike["aws:SourceArn"] == "arn:aws:logs:us-east-1:123456789012:*"
    ])
    error_message = "With flow_logs_s3_backup the component key must let delivery.logs.amazonaws.com kms:GenerateDataKey* (and nothing else) for this account's CloudWatch Logs."
  }
}
