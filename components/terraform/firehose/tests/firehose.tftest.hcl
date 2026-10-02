# Mock-provider tests: no AWS credentials, no network. Run from the component
# directory with `terraform init -backend=false && terraform test`.

# override_during = plan: mocked computed values (ARNs, account ID) are known
# at plan, so plan-only runs can assert on the rendered policies.
mock_provider "aws" {
  override_during = plan

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:us-east-1:123456789012:log-group:/aws/kinesisfirehose/test-raw"
    }
  }
}

override_resource {
  override_during = plan
  target          = aws_iam_role.delivery
  values          = { arn = "arn:aws:iam::123456789012:role/test-raw-delivery", id = "test-raw-delivery" }
}

override_resource {
  override_during = plan
  target          = aws_iam_role.source
  values          = { arn = "arn:aws:iam::123456789012:role/test-raw-source", id = "test-raw-source" }
}

variables {
  region = "us-east-1"
  name   = "raw"
  tags = {
    Environment = "test"
    Tenant      = "fnx"
    ManagedBy   = "Terraform"
  }
  s3_bucket_arn = "arn:aws:s3:::fnx-test-raw"
  kms_key_arn   = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"
}

run "direct_put_defaults" {
  command = plan

  assert {
    condition = (
      aws_kinesis_firehose_delivery_stream.this[0].name == "test-raw"
      && aws_kinesis_firehose_delivery_stream.this[0].destination == "extended_s3"
      && length(aws_kinesis_firehose_delivery_stream.this[0].kinesis_source_configuration) == 0
    )
    error_message = "A direct put stream is named <Environment>-<name>, delivers to extended_s3 and has no Kinesis source."
  }

  assert {
    condition = (
      aws_kinesis_firehose_delivery_stream.this[0].server_side_encryption[0].enabled
      && aws_kinesis_firehose_delivery_stream.this[0].server_side_encryption[0].key_type == "AWS_OWNED_CMK"
    )
    error_message = "A direct put stream without server_side_encryption_kms_key_arn is encrypted with an AWS owned key."
  }

  assert {
    condition = (
      length(aws_iam_role.source) == 0 && output.source_role_arn == null
      && output.role_arn == "arn:aws:iam::123456789012:role/test-raw-delivery"
    )
    error_message = "A direct put stream gets the delivery role only."
  }

  assert {
    condition = (
      aws_kinesis_firehose_delivery_stream.this[0].extended_s3_configuration[0].bucket_arn == "arn:aws:s3:::fnx-test-raw"
      && aws_kinesis_firehose_delivery_stream.this[0].extended_s3_configuration[0].role_arn == "arn:aws:iam::123456789012:role/test-raw-delivery"
      && aws_kinesis_firehose_delivery_stream.this[0].extended_s3_configuration[0].kms_key_arn == var.kms_key_arn
      && aws_kinesis_firehose_delivery_stream.this[0].extended_s3_configuration[0].compression_format == "UNCOMPRESSED"
      && aws_kinesis_firehose_delivery_stream.this[0].extended_s3_configuration[0].buffering_size == 5
      && aws_kinesis_firehose_delivery_stream.this[0].extended_s3_configuration[0].buffering_interval == 300
    )
    error_message = "extended_s3 uses the bucket, the delivery role, the CMK and the default buffering/compression."
  }

  assert {
    condition = (
      aws_cloudwatch_log_group.this[0].name == "/aws/kinesisfirehose/test-raw"
      && aws_cloudwatch_log_group.this[0].kms_key_id == var.kms_key_arn
      && aws_cloudwatch_log_group.this[0].retention_in_days == 90
      && aws_cloudwatch_log_stream.delivery[0].name == "DestinationDelivery"
      && aws_kinesis_firehose_delivery_stream.this[0].extended_s3_configuration[0].cloudwatch_logging_options[0].enabled
      && aws_kinesis_firehose_delivery_stream.this[0].extended_s3_configuration[0].cloudwatch_logging_options[0].log_group_name == "/aws/kinesisfirehose/test-raw"
      && aws_kinesis_firehose_delivery_stream.this[0].extended_s3_configuration[0].cloudwatch_logging_options[0].log_stream_name == "DestinationDelivery"
      && output.log_group_name == "/aws/kinesisfirehose/test-raw"
    )
    error_message = "Delivery errors go to a KMS-encrypted log group with retention, through its DestinationDelivery stream."
  }
}

run "direct_put_with_customer_managed_key" {
  command = plan

  variables {
    server_side_encryption_kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/99999999-8888-7777-6666-555555555555"
  }

  assert {
    condition = (
      aws_kinesis_firehose_delivery_stream.this[0].server_side_encryption[0].enabled
      && aws_kinesis_firehose_delivery_stream.this[0].server_side_encryption[0].key_type == "CUSTOMER_MANAGED_CMK"
      && aws_kinesis_firehose_delivery_stream.this[0].server_side_encryption[0].key_arn == "arn:aws:kms:us-east-1:123456789012:key/99999999-8888-7777-6666-555555555555"
    )
    error_message = "server_side_encryption_kms_key_arn encrypts a direct put stream with that CUSTOMER_MANAGED_CMK."
  }
}

run "kinesis_source" {
  command = plan

  variables {
    kinesis_source_stream_arn  = "arn:aws:kinesis:us-east-1:123456789012:stream/test-ingest"
    kinesis_source_kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    s3_prefix                  = "data/year=!{timestamp:yyyy}/month=!{timestamp:MM}/"
    s3_error_output_prefix     = "errors/!{firehose:error-output-type}/"
    buffering_size             = 128
    buffering_interval         = 60
    compression_format         = "GZIP"
  }

  assert {
    condition = (
      aws_kinesis_firehose_delivery_stream.this[0].kinesis_source_configuration[0].kinesis_stream_arn == "arn:aws:kinesis:us-east-1:123456789012:stream/test-ingest"
      && aws_kinesis_firehose_delivery_stream.this[0].kinesis_source_configuration[0].role_arn == "arn:aws:iam::123456789012:role/test-raw-source"
      && output.source_role_arn == "arn:aws:iam::123456789012:role/test-raw-source"
    )
    error_message = "A Kinesis source reads the stream through the source role."
  }

  assert {
    condition     = length(aws_kinesis_firehose_delivery_stream.this[0].server_side_encryption) == 0
    error_message = "A Kinesis source stream gets no server_side_encryption block (Firehose rejects it)."
  }

  assert {
    condition = (
      aws_kinesis_firehose_delivery_stream.this[0].extended_s3_configuration[0].prefix == "data/year=!{timestamp:yyyy}/month=!{timestamp:MM}/"
      && aws_kinesis_firehose_delivery_stream.this[0].extended_s3_configuration[0].error_output_prefix == "errors/!{firehose:error-output-type}/"
      && aws_kinesis_firehose_delivery_stream.this[0].extended_s3_configuration[0].buffering_size == 128
      && aws_kinesis_firehose_delivery_stream.this[0].extended_s3_configuration[0].buffering_interval == 60
      && aws_kinesis_firehose_delivery_stream.this[0].extended_s3_configuration[0].compression_format == "GZIP"
    )
    error_message = "Prefixes, buffering and compression pass through."
  }
}

run "source_role_reads_only_its_stream" {
  command = plan

  variables {
    kinesis_source_stream_arn  = "arn:aws:kinesis:us-east-1:123456789012:stream/test-ingest"
    kinesis_source_kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
  }

  assert {
    condition = (
      jsondecode(aws_iam_role_policy.source[0].policy).Statement[0].Resource == "arn:aws:kinesis:us-east-1:123456789012:stream/test-ingest"
      && toset(jsondecode(aws_iam_role_policy.source[0].policy).Statement[0].Action) == toset(["kinesis:DescribeStream", "kinesis:GetRecords", "kinesis:GetShardIterator", "kinesis:ListShards"])
    )
    error_message = "The source role gets DescribeStream, GetRecords, GetShardIterator and ListShards on the source stream only."
  }

  assert {
    condition = (
      jsondecode(aws_iam_role_policy.source[0].policy).Statement[1].Action == ["kms:Decrypt"]
      && jsondecode(aws_iam_role_policy.source[0].policy).Statement[1].Resource == "arn:aws:kms:us-east-1:123456789012:key/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
      && jsondecode(aws_iam_role_policy.source[0].policy).Statement[1].Condition.StringEquals["kms:ViaService"] == "kinesis.us-east-1.amazonaws.com"
      && jsondecode(aws_iam_role_policy.source[0].policy).Statement[1].Condition.StringEquals["kms:EncryptionContext:aws:kinesis:arn"] == "arn:aws:kinesis:us-east-1:123456789012:stream/test-ingest"
    )
    error_message = "The source role gets kms:Decrypt on the source key, through Kinesis and for this stream only."
  }

  assert {
    condition = (
      jsondecode(aws_iam_role.source[0].assume_role_policy).Statement[0].Principal.Service == "firehose.amazonaws.com"
      && jsondecode(aws_iam_role.source[0].assume_role_policy).Statement[0].Condition.StringEquals["aws:SourceAccount"] == "123456789012"
    )
    error_message = "The source role trusts Firehose from this account only."
  }
}

run "source_role_without_a_source_key" {
  command = plan

  variables {
    kinesis_source_stream_arn = "arn:aws:kinesis:us-east-1:123456789012:stream/test-ingest"
  }

  assert {
    condition     = length(jsondecode(aws_iam_role_policy.source[0].policy).Statement) == 1
    error_message = "Without kinesis_source_kms_key_arn the source role gets no KMS statement."
  }
}

run "delivery_role_is_scoped_to_exact_arns" {
  command = plan

  assert {
    condition = (
      jsondecode(aws_iam_role.delivery[0].assume_role_policy).Statement[0].Principal.Service == "firehose.amazonaws.com"
      && jsondecode(aws_iam_role.delivery[0].assume_role_policy).Statement[0].Condition.StringEquals["aws:SourceAccount"] == "123456789012"
      && aws_iam_role.delivery[0].name == "test-raw-delivery"
    )
    error_message = "The delivery role is <Environment>-<name>-delivery and trusts Firehose from this account only."
  }

  assert {
    condition = (
      jsondecode(aws_iam_role_policy.delivery[0].policy).Statement[0].Resource == "arn:aws:s3:::fnx-test-raw"
      && toset(jsondecode(aws_iam_role_policy.delivery[0].policy).Statement[0].Action) == toset(["s3:GetBucketLocation", "s3:ListBucket", "s3:ListBucketMultipartUploads"])
      && jsondecode(aws_iam_role_policy.delivery[0].policy).Statement[1].Resource == "arn:aws:s3:::fnx-test-raw/*"
      && toset(jsondecode(aws_iam_role_policy.delivery[0].policy).Statement[1].Action) == toset(["s3:AbortMultipartUpload", "s3:GetObject", "s3:PutObject"])
    )
    error_message = "S3 access is the destination bucket (bucket actions) and its objects (object actions) only."
  }

  assert {
    condition = (
      jsondecode(aws_iam_role_policy.delivery[0].policy).Statement[2].Resource == var.kms_key_arn
      && toset(jsondecode(aws_iam_role_policy.delivery[0].policy).Statement[2].Action) == toset(["kms:GenerateDataKey", "kms:Decrypt"])
      && jsondecode(aws_iam_role_policy.delivery[0].policy).Statement[2].Condition.StringEquals["kms:ViaService"] == "s3.us-east-1.amazonaws.com"
      && jsondecode(aws_iam_role_policy.delivery[0].policy).Statement[2].Condition.StringLike["kms:EncryptionContext:aws:s3:arn"] == ["arn:aws:s3:::fnx-test-raw", "arn:aws:s3:::fnx-test-raw/*"]
    )
    error_message = "KMS use is the CMK, through S3 only, for this bucket only."
  }

  assert {
    condition = (
      jsondecode(aws_iam_role_policy.delivery[0].policy).Statement[3].Action == ["logs:PutLogEvents"]
      && jsondecode(aws_iam_role_policy.delivery[0].policy).Statement[3].Resource == "arn:aws:logs:us-east-1:123456789012:log-group:/aws/kinesisfirehose/test-raw:log-stream:DestinationDelivery"
      && length(jsondecode(aws_iam_role_policy.delivery[0].policy).Statement) == 4
    )
    error_message = "Logging is PutLogEvents on the delivery log stream only, and the policy has nothing else."
  }
}

run "disabled_creates_nothing" {
  command = plan

  variables {
    enabled                   = false
    kinesis_source_stream_arn = "arn:aws:kinesis:us-east-1:123456789012:stream/test-ingest"
  }

  assert {
    condition = (
      length(aws_kinesis_firehose_delivery_stream.this) == 0 && length(aws_iam_role.delivery) == 0
      && length(aws_iam_role.source) == 0 && length(aws_cloudwatch_log_group.this) == 0
      && output.delivery_stream_arn == null && output.delivery_stream_name == null
    )
    error_message = "enabled = false creates no resources."
  }
}

# Negative validations.

run "rejects_sse_key_with_kinesis_source" {
  command = plan

  variables {
    kinesis_source_stream_arn          = "arn:aws:kinesis:us-east-1:123456789012:stream/test-ingest"
    server_side_encryption_kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/99999999-8888-7777-6666-555555555555"
  }

  expect_failures = [var.server_side_encryption_kms_key_arn]
}

run "rejects_source_key_without_source_stream" {
  command = plan

  variables {
    kinesis_source_kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
  }

  expect_failures = [var.kinesis_source_kms_key_arn]
}

run "rejects_source_stream_in_another_region" {
  command = plan

  variables {
    kinesis_source_stream_arn = "arn:aws:kinesis:us-east-2:123456789012:stream/test-ingest"
  }

  expect_failures = [var.kinesis_source_stream_arn]
}

run "rejects_bucket_name_for_bucket_arn" {
  command = plan

  variables {
    s3_bucket_arn = "fnx-test-raw"
  }

  expect_failures = [var.s3_bucket_arn]
}

run "rejects_kms_alias" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:us-east-1:123456789012:alias/main"
  }

  expect_failures = [var.kms_key_arn]
}

run "rejects_dynamic_partitioning_prefix" {
  command = plan

  variables {
    s3_prefix              = "data/source=!{partitionKeyFromQuery:source}/"
    s3_error_output_prefix = "errors/!{firehose:error-output-type}/"
  }

  expect_failures = [var.s3_prefix]
}

run "rejects_expression_prefix_without_error_prefix" {
  command = plan

  variables {
    s3_prefix = "data/year=!{timestamp:yyyy}/"
  }

  expect_failures = [var.s3_prefix]
}

run "rejects_error_prefix_without_error_output_type" {
  command = plan

  variables {
    s3_error_output_prefix = "errors/!{timestamp:yyyy}/"
  }

  expect_failures = [var.s3_error_output_prefix]
}

run "rejects_out_of_range_buffering" {
  command = plan

  variables {
    buffering_size     = 129
    buffering_interval = 901
  }

  expect_failures = [var.buffering_size, var.buffering_interval]
}

run "rejects_unknown_compression" {
  command = plan

  variables {
    compression_format = "gzip"
  }

  expect_failures = [var.compression_format]
}

run "rejects_bad_retention" {
  command = plan

  variables {
    log_retention_days = 10
  }

  expect_failures = [var.log_retention_days]
}

run "rejects_long_name" {
  command = plan

  variables {
    name = "a-name-that-is-much-longer-than-forty-chars"
  }

  expect_failures = [var.name]
}
