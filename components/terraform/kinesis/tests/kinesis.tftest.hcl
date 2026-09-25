# Mock-provider tests: no AWS credentials, no network. Run from the component
# directory with `terraform init -backend=false && terraform test`.

mock_provider "aws" {
  mock_resource "aws_kinesis_stream" {
    defaults = {
      arn = "arn:aws:kinesis:eu-west-2:123456789012:stream/test-data-ingest"
      id  = "test-data-ingest"
    }
  }

  mock_resource "aws_kinesis_stream_consumer" {
    defaults = {
      arn = "arn:aws:kinesis:eu-west-2:123456789012:stream/test-data-ingest/consumer/lambda-processor:1"
    }
  }
}

variables {
  region     = "eu-west-2"
  name       = "data-ingest"
  kms_key_id = "arn:aws:kms:eu-west-2:123456789012:key/00000000-0000-0000-0000-000000000000"
  tags = {
    Environment = "test"
    Tenant      = "fnx"
    ManagedBy   = "Terraform"
  }
}

run "on_demand_defaults_create_a_stream_with_no_shard_count" {
  command = plan

  assert {
    condition     = aws_kinesis_stream.this[0].name == "test-data-ingest"
    error_message = "The stream is named <Environment>-<name>."
  }

  assert {
    condition     = aws_kinesis_stream.this[0].stream_mode_details[0].stream_mode == "ON_DEMAND"
    error_message = "stream_mode defaults to ON_DEMAND."
  }

  assert {
    condition     = aws_kinesis_stream.this[0].shard_count == null
    error_message = "shard_count is not set (null) in ON_DEMAND mode."
  }
}

run "encryption_is_always_kms" {
  command = plan

  assert {
    condition     = aws_kinesis_stream.this[0].encryption_type == "KMS"
    error_message = "encryption_type is always KMS; there is no unencrypted option."
  }

  assert {
    condition     = aws_kinesis_stream.this[0].kms_key_id == var.kms_key_id
    error_message = "kms_key_id is passed through."
  }
}

run "rejects_shard_count_with_on_demand" {
  command = plan

  variables {
    stream_mode = "ON_DEMAND"
    shard_count = 4
  }

  expect_failures = [var.shard_count]
}

run "rejects_missing_shard_count_with_provisioned" {
  command = plan

  variables {
    stream_mode = "PROVISIONED"
  }

  expect_failures = [var.shard_count]
}

run "rejects_zero_shard_count_with_provisioned" {
  command = plan

  variables {
    stream_mode = "PROVISIONED"
    shard_count = 0
  }

  expect_failures = [var.shard_count]
}

run "provisioned_mode_sets_shard_count" {
  command = plan

  variables {
    stream_mode = "PROVISIONED"
    shard_count = 4
  }

  assert {
    condition     = aws_kinesis_stream.this[0].stream_mode_details[0].stream_mode == "PROVISIONED"
    error_message = "stream_mode is passed through as PROVISIONED."
  }

  assert {
    condition     = aws_kinesis_stream.this[0].shard_count == 4
    error_message = "shard_count is passed through in PROVISIONED mode."
  }
}

run "rejects_an_out_of_range_retention_period" {
  command = plan

  variables {
    retention_period = 23
  }

  expect_failures = [var.retention_period]
}

run "rejects_a_retention_period_above_the_maximum" {
  command = plan

  variables {
    retention_period = 8761
  }

  expect_failures = [var.retention_period]
}

run "retention_period_defaults_to_24_hours" {
  command = plan

  assert {
    condition     = aws_kinesis_stream.this[0].retention_period == 24
    error_message = "retention_period defaults to 24 hours."
  }
}

run "rejects_an_unsupported_shard_level_metric" {
  command = plan

  variables {
    shard_level_metrics = ["NotARealMetric"]
  }

  expect_failures = [var.shard_level_metrics]
}

run "shard_level_metrics_are_passed_through" {
  command = plan

  variables {
    shard_level_metrics = ["IncomingBytes", "IncomingRecords"]
  }

  assert {
    condition     = aws_kinesis_stream.this[0].shard_level_metrics == toset(["IncomingBytes", "IncomingRecords"])
    error_message = "shard_level_metrics is passed through."
  }
}

run "enforce_consumer_deletion_defaults_to_false" {
  command = plan

  assert {
    condition     = aws_kinesis_stream.this[0].enforce_consumer_deletion == false
    error_message = "enforce_consumer_deletion defaults to false."
  }
}

run "rejects_an_empty_kms_key_id" {
  command = plan

  variables {
    kms_key_id = ""
  }

  expect_failures = [var.kms_key_id]
}

run "the_consumer_map_creates_consumers" {
  command = apply

  variables {
    consumers = {
      lambda-processor = {}
      firehose-delivery = {
        enabled = true
      }
    }
  }

  assert {
    condition     = length(aws_kinesis_stream_consumer.this) == 2
    error_message = "Every enabled entry in the consumers map creates an aws_kinesis_stream_consumer."
  }

  assert {
    condition     = aws_kinesis_stream_consumer.this["lambda-processor"].name == "lambda-processor"
    error_message = "Each consumer's name is its map key."
  }

  assert {
    condition     = aws_kinesis_stream_consumer.this["lambda-processor"].stream_arn == aws_kinesis_stream.this[0].arn
    error_message = "Each consumer is registered on this stream."
  }

  assert {
    condition     = output.consumer_arns["lambda-processor"] == aws_kinesis_stream_consumer.this["lambda-processor"].arn
    error_message = "consumer_arns reports every created consumer's ARN, keyed by name."
  }
}

run "a_disabled_consumer_entry_creates_no_consumer" {
  command = plan

  variables {
    consumers = {
      lambda-processor = {
        enabled = false
      }
    }
  }

  assert {
    condition     = length(aws_kinesis_stream_consumer.this) == 0
    error_message = "A consumers entry with enabled = false creates no aws_kinesis_stream_consumer."
  }
}

run "reader_kms_policy_grants_scoped_kms_decrypt" {
  command = apply

  assert {
    condition = (
      jsondecode(output.reader_kms_policy).Statement[0].Sid == "AllowKinesisStreamKMSRead"
      && jsondecode(output.reader_kms_policy).Statement[0].Effect == "Allow"
      && jsondecode(output.reader_kms_policy).Statement[0].Action == ["kms:Decrypt"]
      && jsondecode(output.reader_kms_policy).Statement[0].Resource == var.kms_key_id
    )
    error_message = "reader_kms_policy grants exactly kms:Decrypt on kms_key_id."
  }

  assert {
    condition = (
      jsondecode(output.reader_kms_policy).Statement[0].Condition.StringEquals["kms:ViaService"] == "kinesis.${var.region}.amazonaws.com"
      && jsondecode(output.reader_kms_policy).Statement[0].Condition.StringEquals["kms:EncryptionContext:aws:kinesis:arn"] == aws_kinesis_stream.this[0].arn
    )
    error_message = "reader_kms_policy is scoped to calls made via Kinesis for this stream's own encryption context."
  }
}

run "disabled_creates_nothing" {
  command = plan

  variables {
    enabled = false
    consumers = {
      lambda-processor = {}
    }
  }

  assert {
    condition     = length(aws_kinesis_stream.this) == 0 && length(aws_kinesis_stream_consumer.this) == 0
    error_message = "enabled = false must create nothing, including any consumers."
  }

  assert {
    condition     = output.stream_arn == null && output.stream_name == null && output.stream_id == null
    error_message = "Outputs are null when disabled."
  }

  assert {
    condition     = output.reader_kms_policy == null
    error_message = "reader_kms_policy is null when disabled."
  }
}
