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

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
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

  assert {
    condition = (
      length(aws_kinesis_firehose_delivery_stream.this[0].extended_s3_configuration[0].processing_configuration) == 0
      && length(aws_kinesis_firehose_delivery_stream.this[0].extended_s3_configuration[0].dynamic_partitioning_configuration) == 0
      && length(aws_kinesis_firehose_delivery_stream.this[0].extended_s3_configuration[0].data_format_conversion_configuration) == 0
    )
    error_message = "Without the optional features there is no processing, partitioning or conversion block."
  }
}

# Data format conversion.

run "conversion_parquet_defaults" {
  command = plan

  variables {
    buffering_size = 64
    data_format_conversion = {
      schema_configuration = { database_name = "fnx_test_lake", table_name = "raw_events" }
    }
  }

  assert {
    condition = (
      aws_kinesis_firehose_delivery_stream.this[0].extended_s3_configuration[0].data_format_conversion_configuration[0].enabled
      && length(aws_kinesis_firehose_delivery_stream.this[0].extended_s3_configuration[0].data_format_conversion_configuration[0].input_format_configuration[0].deserializer[0].open_x_json_ser_de) == 1
      && length(aws_kinesis_firehose_delivery_stream.this[0].extended_s3_configuration[0].data_format_conversion_configuration[0].input_format_configuration[0].deserializer[0].hive_json_ser_de) == 0
      && aws_kinesis_firehose_delivery_stream.this[0].extended_s3_configuration[0].data_format_conversion_configuration[0].output_format_configuration[0].serializer[0].parquet_ser_de[0].compression == "SNAPPY"
      && length(aws_kinesis_firehose_delivery_stream.this[0].extended_s3_configuration[0].data_format_conversion_configuration[0].output_format_configuration[0].serializer[0].orc_ser_de) == 0
    )
    error_message = "Conversion defaults to OpenX JSON in, SNAPPY Parquet out."
  }

  assert {
    condition = (
      aws_kinesis_firehose_delivery_stream.this[0].extended_s3_configuration[0].data_format_conversion_configuration[0].schema_configuration[0].database_name == "fnx_test_lake"
      && aws_kinesis_firehose_delivery_stream.this[0].extended_s3_configuration[0].data_format_conversion_configuration[0].schema_configuration[0].table_name == "raw_events"
      && aws_kinesis_firehose_delivery_stream.this[0].extended_s3_configuration[0].data_format_conversion_configuration[0].schema_configuration[0].region == "us-east-1"
      && aws_kinesis_firehose_delivery_stream.this[0].extended_s3_configuration[0].data_format_conversion_configuration[0].schema_configuration[0].catalog_id == "123456789012"
      && aws_kinesis_firehose_delivery_stream.this[0].extended_s3_configuration[0].data_format_conversion_configuration[0].schema_configuration[0].version_id == "LATEST"
      && aws_kinesis_firehose_delivery_stream.this[0].extended_s3_configuration[0].data_format_conversion_configuration[0].schema_configuration[0].role_arn == "arn:aws:iam::123456789012:role/test-raw-delivery"
    )
    error_message = "The schema is read from the Glue table in this region and account, version LATEST, with the delivery role."
  }

  assert {
    condition = (
      jsondecode(aws_iam_role_policy.delivery[0].policy).Statement[4].Sid == "GlueSchema"
      && toset(jsondecode(aws_iam_role_policy.delivery[0].policy).Statement[4].Action) == toset(["glue:GetTable", "glue:GetTableVersion", "glue:GetTableVersions"])
      && jsondecode(aws_iam_role_policy.delivery[0].policy).Statement[4].Resource == [
        "arn:aws:glue:us-east-1:123456789012:catalog",
        "arn:aws:glue:us-east-1:123456789012:database/fnx_test_lake",
        "arn:aws:glue:us-east-1:123456789012:table/fnx_test_lake/raw_events",
      ]
      && length(jsondecode(aws_iam_role_policy.delivery[0].policy).Statement) == 5
    )
    error_message = "The delivery role reads exactly the Glue catalog, database and table, and gets no KMS-through-Glue grant without a catalog key."
  }
}

run "conversion_orc_hive_cross_account_encrypted_catalog" {
  command = plan

  variables {
    buffering_size = 128
    data_format_conversion = {
      input_format                = "HIVE_JSON"
      hive_json_timestamp_formats = ["yyyy-MM-dd'T'HH:mm:ss"]
      output_format               = "ORC"
      compression                 = "ZLIB"
      schema_configuration = {
        database_name = "lake"
        table_name    = "events"
        region        = "us-west-2"
        catalog_id    = "210987654321"
        version_id    = "3"
        kms_key_arn   = "arn:aws:kms:us-west-2:210987654321:key/cccccccc-dddd-eeee-ffff-000000000000"
      }
    }
  }

  assert {
    condition = (
      aws_kinesis_firehose_delivery_stream.this[0].extended_s3_configuration[0].data_format_conversion_configuration[0].input_format_configuration[0].deserializer[0].hive_json_ser_de[0].timestamp_formats == tolist(["yyyy-MM-dd'T'HH:mm:ss"])
      && aws_kinesis_firehose_delivery_stream.this[0].extended_s3_configuration[0].data_format_conversion_configuration[0].output_format_configuration[0].serializer[0].orc_ser_de[0].compression == "ZLIB"
      && aws_kinesis_firehose_delivery_stream.this[0].extended_s3_configuration[0].data_format_conversion_configuration[0].schema_configuration[0].catalog_id == "210987654321"
      && aws_kinesis_firehose_delivery_stream.this[0].extended_s3_configuration[0].data_format_conversion_configuration[0].schema_configuration[0].version_id == "3"
    )
    error_message = "Hive JSON in, ZLIB ORC out, against the given catalog and table version."
  }

  assert {
    condition = (
      jsondecode(aws_iam_role_policy.delivery[0].policy).Statement[4].Resource == [
        "arn:aws:glue:us-west-2:210987654321:catalog",
        "arn:aws:glue:us-west-2:210987654321:database/lake",
        "arn:aws:glue:us-west-2:210987654321:table/lake/events",
      ]
      && jsondecode(aws_iam_role_policy.delivery[0].policy).Statement[5].Sid == "KMSThroughGlue"
      && jsondecode(aws_iam_role_policy.delivery[0].policy).Statement[5].Action == ["kms:Decrypt"]
      && jsondecode(aws_iam_role_policy.delivery[0].policy).Statement[5].Resource == "arn:aws:kms:us-west-2:210987654321:key/cccccccc-dddd-eeee-ffff-000000000000"
      && jsondecode(aws_iam_role_policy.delivery[0].policy).Statement[5].Condition.StringEquals["kms:ViaService"] == "glue.us-west-2.amazonaws.com"
    )
    error_message = "The Glue grant follows the schema's region and catalog, and an encrypted catalog adds kms:Decrypt through Glue."
  }
}

run "conversion_disabled_adds_nothing" {
  command = plan

  variables {
    data_format_conversion = {
      enabled              = false
      schema_configuration = { database_name = "lake", table_name = "events" }
    }
  }

  assert {
    condition = (
      length(aws_kinesis_firehose_delivery_stream.this[0].extended_s3_configuration[0].data_format_conversion_configuration) == 0
      && length(jsondecode(aws_iam_role_policy.delivery[0].policy).Statement) == 4
    )
    error_message = "enabled = false adds no conversion block and no Glue grant (and skips the 64 MiB rule)."
  }
}

run "rejects_conversion_below_64_mib" {
  command = plan

  variables {
    buffering_size = 63
    data_format_conversion = {
      schema_configuration = { database_name = "lake", table_name = "events" }
    }
  }

  expect_failures = [var.data_format_conversion]
}

run "rejects_conversion_with_s3_compression" {
  command = plan

  variables {
    buffering_size     = 64
    compression_format = "GZIP"
    data_format_conversion = {
      schema_configuration = { database_name = "lake", table_name = "events" }
    }
  }

  expect_failures = [var.data_format_conversion]
}

run "rejects_orc_with_parquet_compression" {
  command = plan

  variables {
    buffering_size = 64
    data_format_conversion = {
      output_format        = "ORC"
      compression          = "GZIP"
      schema_configuration = { database_name = "lake", table_name = "events" }
    }
  }

  expect_failures = [var.data_format_conversion]
}

# Dynamic partitioning.

run "dynamic_partitioning_with_jq" {
  command = plan

  variables {
    buffering_size         = 64
    s3_prefix              = "data/source=!{partitionKeyFromQuery:source}/type=!{partitionKeyFromQuery:event_type}/year=!{timestamp:yyyy}/"
    s3_error_output_prefix = "errors/!{firehose:error-output-type}/"
    dynamic_partitioning = {
      retry_duration   = 600
      jq_queries       = { source = ".source", event_type = ".detail.type" }
      append_delimiter = true
    }
  }

  assert {
    condition = (
      aws_kinesis_firehose_delivery_stream.this[0].extended_s3_configuration[0].dynamic_partitioning_configuration[0].enabled
      && aws_kinesis_firehose_delivery_stream.this[0].extended_s3_configuration[0].dynamic_partitioning_configuration[0].retry_duration == 600
    )
    error_message = "Dynamic partitioning is enabled with the given retry duration."
  }

  assert {
    condition = (
      aws_kinesis_firehose_delivery_stream.this[0].extended_s3_configuration[0].processing_configuration[0].enabled
      && length(aws_kinesis_firehose_delivery_stream.this[0].extended_s3_configuration[0].processing_configuration[0].processors) == 2
      && aws_kinesis_firehose_delivery_stream.this[0].extended_s3_configuration[0].processing_configuration[0].processors[0].type == "MetadataExtraction"
      && {
        for p in aws_kinesis_firehose_delivery_stream.this[0].extended_s3_configuration[0].processing_configuration[0].processors[0].parameters : p.parameter_name => p.parameter_value
        } == {
        MetadataExtractionQuery = "{event_type:.detail.type,source:.source}"
        JsonParsingEngine       = "JQ-1.6"
      }
      && aws_kinesis_firehose_delivery_stream.this[0].extended_s3_configuration[0].processing_configuration[0].processors[1].type == "AppendDelimiterToRecord"
    )
    error_message = "jq_queries render one JQ-1.6 MetadataExtraction processor, followed by AppendDelimiterToRecord."
  }
}

run "dynamic_partitioning_default_retry" {
  command = plan

  variables {
    buffering_size         = 64
    s3_prefix              = "data/source=!{partitionKeyFromQuery:source}/"
    s3_error_output_prefix = "errors/!{firehose:error-output-type}/"
    dynamic_partitioning   = { jq_queries = { source = ".source" } }
  }

  assert {
    condition = (
      aws_kinesis_firehose_delivery_stream.this[0].extended_s3_configuration[0].dynamic_partitioning_configuration[0].retry_duration == 300
      && length(aws_kinesis_firehose_delivery_stream.this[0].extended_s3_configuration[0].processing_configuration[0].processors) == 1
    )
    error_message = "retry_duration defaults to 300 and append_delimiter is off by default."
  }
}

run "rejects_dynamic_partitioning_below_64_mib" {
  command = plan

  variables {
    s3_prefix              = "data/source=!{partitionKeyFromQuery:source}/"
    s3_error_output_prefix = "errors/!{firehose:error-output-type}/"
    dynamic_partitioning   = { jq_queries = { source = ".source" } }
  }

  expect_failures = [var.dynamic_partitioning]
}

run "rejects_dynamic_partitioning_without_partition_key_in_prefix" {
  command = plan

  variables {
    buffering_size         = 64
    s3_prefix              = "data/year=!{timestamp:yyyy}/"
    s3_error_output_prefix = "errors/!{firehose:error-output-type}/"
    dynamic_partitioning   = { jq_queries = { source = ".source" } }
  }

  expect_failures = [var.s3_prefix]
}

run "rejects_undefined_query_key_in_prefix" {
  command = plan

  variables {
    buffering_size         = 64
    s3_prefix              = "data/source=!{partitionKeyFromQuery:source}/region=!{partitionKeyFromQuery:region}/"
    s3_error_output_prefix = "errors/!{firehose:error-output-type}/"
    dynamic_partitioning   = { jq_queries = { source = ".source" } }
  }

  expect_failures = [var.s3_prefix]
}

run "rejects_lambda_key_without_lambda" {
  command = plan

  variables {
    buffering_size         = 64
    s3_prefix              = "data/customer=!{partitionKeyFromLambda:customer_id}/"
    s3_error_output_prefix = "errors/!{firehose:error-output-type}/"
    dynamic_partitioning   = {}
  }

  expect_failures = [var.s3_prefix]
}

run "rejects_bad_retry_duration" {
  command = plan

  variables {
    buffering_size         = 64
    s3_prefix              = "data/source=!{partitionKeyFromQuery:source}/"
    s3_error_output_prefix = "errors/!{firehose:error-output-type}/"
    dynamic_partitioning   = { retry_duration = 7201, jq_queries = { source = ".source" } }
  }

  expect_failures = [var.dynamic_partitioning]
}

# Lambda processor.

run "lambda_processor_with_lambda_partition_keys" {
  command = plan

  variables {
    buffering_size          = 64
    processor_lambda_arn    = "arn:aws:lambda:us-east-1:123456789012:function:test-transform:live"
    processor_lambda_config = { buffer_size_in_mbs = 3, number_of_retries = 5 }
    s3_prefix               = "data/customer=!{partitionKeyFromLambda:customer_id}/"
    s3_error_output_prefix  = "errors/!{firehose:error-output-type}/"
    dynamic_partitioning    = {}
  }

  assert {
    condition = (
      length(aws_kinesis_firehose_delivery_stream.this[0].extended_s3_configuration[0].processing_configuration[0].processors) == 1
      && aws_kinesis_firehose_delivery_stream.this[0].extended_s3_configuration[0].processing_configuration[0].processors[0].type == "Lambda"
      && {
        for p in aws_kinesis_firehose_delivery_stream.this[0].extended_s3_configuration[0].processing_configuration[0].processors[0].parameters : p.parameter_name => p.parameter_value
        } == {
        LambdaArn               = "arn:aws:lambda:us-east-1:123456789012:function:test-transform:live"
        BufferSizeInMBs         = "3"
        BufferIntervalInSeconds = "60"
        NumberOfRetries         = "5"
      }
    )
    error_message = "processor_lambda_arn renders one Lambda processor with its buffering and retries (no MetadataExtraction without jq_queries)."
  }

  assert {
    condition = (
      jsondecode(aws_iam_role_policy.delivery[0].policy).Statement[4].Sid == "LambdaProcessor"
      && toset(jsondecode(aws_iam_role_policy.delivery[0].policy).Statement[4].Action) == toset(["lambda:InvokeFunction", "lambda:GetFunctionConfiguration"])
      && jsondecode(aws_iam_role_policy.delivery[0].policy).Statement[4].Resource == [
        "arn:aws:lambda:us-east-1:123456789012:function:test-transform:live",
        "arn:aws:lambda:us-east-1:123456789012:function:test-transform",
      ]
      && length(jsondecode(aws_iam_role_policy.delivery[0].policy).Statement) == 5
    )
    error_message = "The delivery role invokes exactly the given qualified ARN and its unqualified function ARN."
  }
}

run "lambda_processor_then_jq" {
  command = plan

  variables {
    buffering_size         = 64
    processor_lambda_arn   = "arn:aws:lambda:us-east-1:123456789012:function:test-transform"
    s3_prefix              = "data/source=!{partitionKeyFromQuery:source}/"
    s3_error_output_prefix = "errors/!{firehose:error-output-type}/"
    dynamic_partitioning   = { jq_queries = { source = ".source" } }
  }

  assert {
    condition = (
      [for p in aws_kinesis_firehose_delivery_stream.this[0].extended_s3_configuration[0].processing_configuration[0].processors : p.type] == ["Lambda", "MetadataExtraction"]
      && jsondecode(aws_iam_role_policy.delivery[0].policy).Statement[4].Resource == ["arn:aws:lambda:us-east-1:123456789012:function:test-transform"]
    )
    error_message = "The Lambda runs before JQ extraction; an unqualified ARN is granted once."
  }
}

run "lambda_processor_without_partitioning" {
  command = plan

  variables {
    processor_lambda_arn = "arn:aws:lambda:us-east-1:123456789012:function:test-transform:1"
  }

  assert {
    condition = (
      length(aws_kinesis_firehose_delivery_stream.this[0].extended_s3_configuration[0].processing_configuration[0].processors) == 1
      && length(aws_kinesis_firehose_delivery_stream.this[0].extended_s3_configuration[0].dynamic_partitioning_configuration) == 0
    )
    error_message = "A Lambda processor works without dynamic partitioning or the 64 MiB minimum."
  }
}

run "rejects_lambda_name_for_arn" {
  command = plan

  variables {
    processor_lambda_arn = "test-transform"
  }

  expect_failures = [var.processor_lambda_arn]
}

run "rejects_out_of_range_lambda_config" {
  command = plan

  variables {
    processor_lambda_arn    = "arn:aws:lambda:us-east-1:123456789012:function:test-transform"
    processor_lambda_config = { buffer_size_in_mbs = 4 }
  }

  expect_failures = [var.processor_lambda_config]
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

run "rejects_partition_key_prefix_without_dynamic_partitioning" {
  command = plan

  variables {
    s3_prefix              = "data/source=!{partitionKeyFromQuery:source}/"
    s3_error_output_prefix = "errors/!{firehose:error-output-type}/"
  }

  expect_failures = [var.s3_prefix]
}

run "rejects_partition_key_prefix_with_dynamic_partitioning_disabled" {
  command = plan

  variables {
    buffering_size         = 64
    s3_prefix              = "data/source=!{partitionKeyFromQuery:source}/"
    s3_error_output_prefix = "errors/!{firehose:error-output-type}/"
    dynamic_partitioning   = { enabled = false, jq_queries = { source = ".source" } }
  }

  expect_failures = [var.s3_prefix]
}

run "rejects_error_output_type_in_prefix" {
  command = plan

  variables {
    s3_prefix              = "data/!{firehose:error-output-type}/"
    s3_error_output_prefix = "errors/!{firehose:error-output-type}/"
  }

  expect_failures = [var.s3_prefix]
}

run "rejects_partition_key_in_error_prefix" {
  command = plan

  variables {
    buffering_size         = 64
    s3_prefix              = "data/source=!{partitionKeyFromQuery:source}/"
    s3_error_output_prefix = "errors/!{firehose:error-output-type}/!{partitionKeyFromQuery:source}/"
    dynamic_partitioning   = { jq_queries = { source = ".source" } }
  }

  expect_failures = [var.s3_error_output_prefix]
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
