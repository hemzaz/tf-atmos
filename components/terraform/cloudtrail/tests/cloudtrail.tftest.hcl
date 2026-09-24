# The real AWS provider is used, not a mock: aws_iam_policy_document is
# computed locally, and a mock would return a random string instead of the
# bucket, trust and log-stream policies asserted below. It never reaches AWS:
# credentials are dummies, every check that would call AWS is skipped, and
# caller identity is overridden. The component builds its ARNs from names, so
# the policies are known at plan time.
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

override_data {
  target = data.aws_caller_identity.current
  values = {
    account_id = "123456789012"
  }
}

variables {
  region      = "eu-west-2"
  kms_key_arn = "arn:aws:kms:eu-west-2:123456789012:key/12345678-1234-1234-1234-123456789012"
  tags = {
    Environment = "test"
    Tenant      = "fnx"
    ManagedBy   = "Terraform"
  }
}

run "cis_trail_defaults" {
  command = plan

  assert {
    condition     = aws_cloudtrail.this.name == "test-cloudtrail"
    error_message = "The trail is named <Environment>-<name>."
  }

  assert {
    condition     = aws_cloudtrail.this.is_multi_region_trail && aws_cloudtrail.this.include_global_service_events
    error_message = "The trail must be multi-region and include global service events (CIS 3.1, IAM/root filters)."
  }

  assert {
    condition     = aws_cloudtrail.this.enable_log_file_validation
    error_message = "Log file validation must be on (CIS 3.2)."
  }

  assert {
    condition     = aws_cloudtrail.this.kms_key_id == var.kms_key_arn
    error_message = "Trail log files must be encrypted with the CMK passed in (CIS 3.7)."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.name == "/aws/cloudtrail/test-cloudtrail" && aws_cloudwatch_log_group.this.kms_key_id == var.kms_key_arn && aws_cloudwatch_log_group.this.retention_in_days == 365
    error_message = "The CloudWatch log group is /aws/cloudtrail/<name>, encrypted with the CMK and kept a year."
  }

  assert {
    condition     = aws_s3_bucket.this.bucket == "test-cloudtrail-123456789012"
    error_message = "The log bucket is named <name>-<account id>."
  }

  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.this.rule).apply_server_side_encryption_by_default[0].kms_master_key_id == var.kms_key_arn
    error_message = "The log bucket must be SSE-KMS with the CMK."
  }

  assert {
    condition = (
      aws_s3_bucket_public_access_block.this.block_public_acls
      && aws_s3_bucket_public_access_block.this.block_public_policy
      && aws_s3_bucket_public_access_block.this.ignore_public_acls
      && aws_s3_bucket_public_access_block.this.restrict_public_buckets
    )
    error_message = "The log bucket must block all public access."
  }

  assert {
    condition     = output.cloudtrail_logs_log_group_name == "/aws/cloudtrail/test-cloudtrail"
    error_message = "cloudtrail_logs_log_group_name is what security-monitoring's metric filters read."
  }
}

run "policies_are_scoped_to_this_trail" {
  command = plan

  assert {
    condition = one([
      for st in jsondecode(data.aws_iam_policy_document.bucket.json).Statement : st if st.Sid == "AWSCloudTrailWrite"
    ]).Condition.StringEquals["aws:SourceArn"] == "arn:aws:cloudtrail:eu-west-2:123456789012:trail/test-cloudtrail"
    error_message = "Only this trail may write to the bucket (aws:SourceArn)."
  }

  assert {
    condition = one([
      for st in jsondecode(data.aws_iam_policy_document.bucket.json).Statement : st if st.Sid == "AWSCloudTrailWrite"
    ]).Resource == "arn:aws:s3:::test-cloudtrail-123456789012/AWSLogs/123456789012/*"
    error_message = "The trail may write only under AWSLogs/<this account>/."
  }

  assert {
    condition = one([
      for st in jsondecode(data.aws_iam_policy_document.bucket.json).Statement : st if st.Sid == "DenyInsecureTransport"
    ]).Condition.Bool["aws:SecureTransport"] == "false"
    error_message = "The bucket must deny requests without TLS."
  }

  assert {
    condition     = jsondecode(data.aws_iam_policy_document.assume.json).Statement[0].Condition.StringEquals["aws:SourceArn"] == "arn:aws:cloudtrail:eu-west-2:123456789012:trail/test-cloudtrail"
    error_message = "Only this trail may assume the CloudWatch Logs role."
  }

  assert {
    condition     = jsondecode(data.aws_iam_policy_document.cloudwatch_logs.json).Statement[0].Resource == "arn:aws:logs:eu-west-2:123456789012:log-group:/aws/cloudtrail/test-cloudtrail:log-stream:*"
    error_message = "The role may write only to the trail's own log group."
  }
}

run "rejects_non_arn_kms_key" {
  command = plan

  variables {
    kms_key_arn = "alias/main"
  }

  expect_failures = [var.kms_key_arn]
}

run "rejects_expiry_before_transition" {
  command = plan

  variables {
    bucket_glacier_transition_days = 400
    bucket_expiration_days         = 365
  }

  expect_failures = [aws_s3_bucket_lifecycle_configuration.this]
}
