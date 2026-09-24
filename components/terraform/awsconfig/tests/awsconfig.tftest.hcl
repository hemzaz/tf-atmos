# The real AWS provider is used, not a mock: aws_iam_policy_document is
# computed locally, and a mock would return a random string instead of the
# policies asserted below. It never reaches AWS: credentials are dummies,
# every check that would call AWS is skipped, and caller identity is
# overridden. The component builds its ARNs from names, so the policies are
# known at plan time.
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

run "records_everything_and_delivers_encrypted" {
  command = plan

  assert {
    condition     = aws_config_configuration_recorder.this.recording_group[0].all_supported && aws_config_configuration_recorder.this.recording_group[0].include_global_resource_types
    error_message = "The recorder must record every supported resource type, global ones included (Security Hub Config.1)."
  }

  assert {
    condition     = aws_config_configuration_recorder_status.this.is_enabled
    error_message = "The recorder must be started by default."
  }

  assert {
    condition     = aws_config_delivery_channel.this.s3_bucket_name == "test-awsconfig-123456789012" && aws_config_delivery_channel.this.s3_kms_key_arn == var.kms_key_arn
    error_message = "Snapshots go to the component's bucket, encrypted with the CMK."
  }

  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.this.rule).apply_server_side_encryption_by_default[0].kms_master_key_id == var.kms_key_arn
    error_message = "The bucket must be SSE-KMS with the CMK."
  }

  assert {
    condition = (
      aws_s3_bucket_public_access_block.this.block_public_acls
      && aws_s3_bucket_public_access_block.this.block_public_policy
      && aws_s3_bucket_public_access_block.this.ignore_public_acls
      && aws_s3_bucket_public_access_block.this.restrict_public_buckets
    )
    error_message = "The bucket must block all public access."
  }

  assert {
    condition     = aws_iam_role_policy_attachment.config.policy_arn == "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
    error_message = "The recorder role uses the AWS managed AWS_ConfigRole policy."
  }
}

run "policies_are_scoped_to_this_account_and_bucket" {
  command = plan

  assert {
    condition     = jsondecode(data.aws_iam_policy_document.assume.json).Statement[0].Condition.StringEquals["aws:SourceAccount"] == "123456789012"
    error_message = "Only AWS Config acting for this account may assume the recorder role."
  }

  assert {
    condition = alltrue([
      for st in jsondecode(data.aws_iam_policy_document.bucket.json).Statement :
      st.Condition.StringEquals["aws:SourceAccount"] == "123456789012" if try(st.Principal.Service, "") == "config.amazonaws.com"
    ])
    error_message = "Every AWS Config bucket statement is limited to this account (aws:SourceAccount)."
  }

  assert {
    condition = one([
      for st in jsondecode(data.aws_iam_policy_document.bucket.json).Statement : st if st.Sid == "AWSConfigBucketDelivery"
    ]).Resource == "arn:aws:s3:::test-awsconfig-123456789012/AWSLogs/123456789012/Config/*"
    error_message = "AWS Config may write only under AWSLogs/<this account>/Config/."
  }

  assert {
    condition = one([
      for st in jsondecode(data.aws_iam_policy_document.bucket.json).Statement : st if st.Sid == "DenyInsecureTransport"
    ]).Condition.Bool["aws:SecureTransport"] == "false"
    error_message = "The bucket must deny requests without TLS."
  }

  assert {
    condition = one([
      for st in jsondecode(data.aws_iam_policy_document.delivery.json).Statement : st if st.Sid == "EncryptSnapshots"
    ]).Resource == var.kms_key_arn
    error_message = "The role may use only the CMK it delivers with."
  }
}

run "rejects_non_arn_kms_key" {
  command = plan

  variables {
    kms_key_arn = "alias/main"
  }

  expect_failures = [var.kms_key_arn]
}

run "rejects_unknown_delivery_frequency" {
  command = plan

  variables {
    delivery_frequency = "Daily"
  }

  expect_failures = [var.delivery_frequency]
}
