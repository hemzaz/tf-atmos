# Offline tests for event_source_mappings, set up as lambda.tftest.hcl (real
# AWS provider, dummy credentials, plan only). No run here sets an input that
# fetches data.aws_caller_identity.current or the S3 prefix list, so nothing
# reaches AWS. aws_iam_policy_document is computed locally, so the derived
# source grants can be asserted.
# Run: terraform init -backend=false && terraform test

provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
}

variables {
  region        = "us-east-1"
  function_name = "orders"
  handler       = "index.handler"
  s3_bucket     = "test-artifacts"
  s3_key        = "orders/1.0.0.zip"
  tags = {
    Environment = "test"
    ManagedBy   = "Terraform"
  }
}

run "no_mappings_create_nothing" {
  command = plan

  assert {
    condition     = length(aws_lambda_event_source_mapping.this) == 0 && length(aws_iam_role_policy.event_sources) == 0
    error_message = "The default (empty) event_source_mappings creates no mapping and no source grant."
  }

  assert {
    condition     = length(aws_iam_role_policy.delivery) == 0
    error_message = "The default (empty) event_source_mappings adds no delivery policy."
  }
}

run "sqs_mapping_and_scoped_read_grant" {
  command = plan

  variables {
    event_source_mappings = {
      orders = {
        event_source_arn                   = "arn:aws:sqs:us-east-1:123456789012:test-orders"
        batch_size                         = 50
        maximum_batching_window_in_seconds = 5
        function_response_types            = ["ReportBatchItemFailures"]
        scaling_config                     = { maximum_concurrency = 5 }
        filter_criteria = {
          filter = [{ pattern = jsonencode({ body = { type = ["order"] } }) }]
        }
      }
    }
    event_source_kms_key_arns = ["arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000"]
  }

  assert {
    condition = (
      aws_lambda_event_source_mapping.this["orders"].event_source_arn == "arn:aws:sqs:us-east-1:123456789012:test-orders"
      && aws_lambda_event_source_mapping.this["orders"].function_name == "test-orders"
      && aws_lambda_event_source_mapping.this["orders"].batch_size == 50
      && aws_lambda_event_source_mapping.this["orders"].maximum_batching_window_in_seconds == 5
      && aws_lambda_event_source_mapping.this["orders"].scaling_config[0].maximum_concurrency == 5
      && aws_lambda_event_source_mapping.this["orders"].starting_position == null
      && toset(aws_lambda_event_source_mapping.this["orders"].function_response_types) == toset(["ReportBatchItemFailures"])
      && length(aws_lambda_event_source_mapping.this["orders"].filter_criteria[0].filter) == 1
    )
    error_message = "The SQS mapping carries its arguments through to aws_lambda_event_source_mapping."
  }

  assert {
    condition     = aws_iam_role_policy.event_sources[0].name == "test-orders-event-sources"
    error_message = "The source grant is <Environment>-<function_name>-event-sources."
  }

  assert {
    condition = (
      toset(one([for s in jsondecode(data.aws_iam_policy_document.event_sources[0].json).Statement : s if s.Sid == "ReadSqsEventSources"]).Action)
      == toset(["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes", "sqs:ChangeMessageVisibility"])
      && one([for s in jsondecode(data.aws_iam_policy_document.event_sources[0].json).Statement : s if s.Sid == "ReadSqsEventSources"]).Resource
      == "arn:aws:sqs:us-east-1:123456789012:test-orders"
    )
    error_message = "The role may consume the queue, and only that queue."
  }

  assert {
    condition = (
      one([for s in jsondecode(data.aws_iam_policy_document.event_sources[0].json).Statement : s if s.Sid == "DecryptEventSources"]).Action == "kms:Decrypt"
      && one([for s in jsondecode(data.aws_iam_policy_document.event_sources[0].json).Statement : s if s.Sid == "DecryptEventSources"]).Resource
      == "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000"
    )
    error_message = "event_source_kms_key_arns gets kms:Decrypt on exactly those keys."
  }

  assert {
    condition     = length(jsondecode(data.aws_iam_policy_document.event_sources[0].json).Statement) == 2
    error_message = "Only the SQS and KMS statements: no Kinesis or DynamoDB grant without such a source."
  }
}

run "kinesis_mapping_with_failure_destination" {
  command = plan

  variables {
    event_source_mappings = {
      ingest = {
        event_source_arn               = "arn:aws:kinesis:us-east-1:123456789012:stream/test-ingest"
        starting_position              = "LATEST"
        batch_size                     = 100
        parallelization_factor         = 10
        maximum_retry_attempts         = 3
        maximum_record_age_in_seconds  = 3600
        bisect_batch_on_function_error = true
        tumbling_window_in_seconds     = 0
        destination_config = {
          on_failure = { destination_arn = "arn:aws:sqs:us-east-1:123456789012:test-ingest-dlq" }
        }
      }
    }
  }

  assert {
    condition = (
      aws_lambda_event_source_mapping.this["ingest"].starting_position == "LATEST"
      && aws_lambda_event_source_mapping.this["ingest"].parallelization_factor == 10
      && aws_lambda_event_source_mapping.this["ingest"].bisect_batch_on_function_error == true
      && aws_lambda_event_source_mapping.this["ingest"].destination_config[0].on_failure[0].destination_arn == "arn:aws:sqs:us-east-1:123456789012:test-ingest-dlq"
    )
    error_message = "The Kinesis mapping carries its stream arguments and on_failure destination."
  }

  assert {
    condition = (
      toset(one([for s in jsondecode(data.aws_iam_policy_document.event_sources[0].json).Statement : s if s.Sid == "ReadKinesisEventSources"]).Action)
      == toset([
        "kinesis:DescribeStream", "kinesis:DescribeStreamSummary", "kinesis:DescribeStreamConsumer", "kinesis:GetRecords",
        "kinesis:GetShardIterator", "kinesis:ListShards", "kinesis:SubscribeToShard",
      ])
      && one([for s in jsondecode(data.aws_iam_policy_document.event_sources[0].json).Statement : s if s.Sid == "ReadKinesisEventSources"]).Resource
      == "arn:aws:kinesis:us-east-1:123456789012:stream/test-ingest"
    )
    error_message = "The role may read the stream, and only that stream."
  }

  assert {
    condition = (
      one([for s in jsondecode(data.aws_iam_policy_document.delivery[0].json).Statement : s if s.Sid == "SendToDeliveryQueues"]).Action == "sqs:SendMessage"
      && one([for s in jsondecode(data.aws_iam_policy_document.delivery[0].json).Statement : s if s.Sid == "SendToDeliveryQueues"]).Resource
      == "arn:aws:sqs:us-east-1:123456789012:test-ingest-dlq"
    )
    error_message = "The mapping's on_failure queue joins the delivery policy: sqs:SendMessage on that queue only."
  }
}

run "kinesis_consumer_grants_consumer_and_stream" {
  command = plan

  variables {
    event_source_mappings = {
      efo = {
        event_source_arn  = "arn:aws:kinesis:us-east-1:123456789012:stream/test-ingest/consumer/orders:1700000000"
        starting_position = "TRIM_HORIZON"
      }
    }
  }

  assert {
    condition = (
      toset(one([for s in jsondecode(data.aws_iam_policy_document.event_sources[0].json).Statement : s if s.Sid == "ReadKinesisEventSources"]).Resource)
      == toset([
        "arn:aws:kinesis:us-east-1:123456789012:stream/test-ingest/consumer/orders:1700000000",
        "arn:aws:kinesis:us-east-1:123456789012:stream/test-ingest",
      ])
    )
    error_message = "An enhanced fan-out consumer gets the consumer ARN and its stream's ARN, nothing wider."
  }
}

run "dynamodb_stream_mapping_and_scoped_read_grant" {
  command = plan

  variables {
    event_source_mappings = {
      changes = {
        event_source_arn  = "arn:aws:dynamodb:us-east-1:123456789012:table/test-orders/stream/2026-01-01T00:00:00.000"
        starting_position = "TRIM_HORIZON"
        destination_config = {
          on_failure = { destination_arn = "arn:aws:sns:us-east-1:123456789012:test-orders-failures" }
        }
      }
    }
  }

  assert {
    condition     = aws_lambda_event_source_mapping.this["changes"].starting_position == "TRIM_HORIZON"
    error_message = "The DynamoDB mapping carries starting_position."
  }

  assert {
    condition = (
      toset(one([for s in jsondecode(data.aws_iam_policy_document.event_sources[0].json).Statement : s if s.Sid == "ReadDynamoDBEventSources"]).Action)
      == toset(["dynamodb:DescribeStream", "dynamodb:GetRecords", "dynamodb:GetShardIterator"])
      && one([for s in jsondecode(data.aws_iam_policy_document.event_sources[0].json).Statement : s if s.Sid == "ReadDynamoDBEventSources"]).Resource
      == "arn:aws:dynamodb:us-east-1:123456789012:table/test-orders/stream/2026-01-01T00:00:00.000"
    )
    error_message = "The role may read the stream, and only that stream."
  }

  assert {
    condition = (
      one([for s in jsondecode(data.aws_iam_policy_document.delivery[0].json).Statement : s if s.Sid == "PublishToDeliveryTopics"]).Action == "sns:Publish"
      && one([for s in jsondecode(data.aws_iam_policy_document.delivery[0].json).Statement : s if s.Sid == "PublishToDeliveryTopics"]).Resource
      == "arn:aws:sns:us-east-1:123456789012:test-orders-failures"
    )
    error_message = "An SNS on_failure destination gets sns:Publish on that topic only."
  }
}

run "rejects_an_unsupported_source_service" {
  command = plan

  variables {
    event_source_mappings = {
      bad = { event_source_arn = "arn:aws:sns:us-east-1:123456789012:test-topic" }
    }
  }

  expect_failures = [var.event_source_mappings]
}

run "rejects_a_wildcard_source" {
  command = plan

  variables {
    event_source_mappings = {
      bad = { event_source_arn = "arn:aws:sqs:us-east-1:123456789012:*" }
    }
  }

  expect_failures = [var.event_source_mappings]
}

run "rejects_sqs_with_starting_position" {
  command = plan

  variables {
    event_source_mappings = {
      bad = {
        event_source_arn  = "arn:aws:sqs:us-east-1:123456789012:test-orders"
        starting_position = "LATEST"
      }
    }
  }

  expect_failures = [var.event_source_mappings]
}

run "rejects_kinesis_without_starting_position" {
  command = plan

  variables {
    event_source_mappings = {
      bad = { event_source_arn = "arn:aws:kinesis:us-east-1:123456789012:stream/test-ingest" }
    }
  }

  expect_failures = [var.event_source_mappings]
}

run "rejects_a_stream_field_on_sqs" {
  command = plan

  variables {
    event_source_mappings = {
      bad = {
        event_source_arn       = "arn:aws:sqs:us-east-1:123456789012:test-orders"
        parallelization_factor = 2
      }
    }
  }

  expect_failures = [var.event_source_mappings]
}

run "rejects_maximum_concurrency_on_a_stream" {
  command = plan

  variables {
    event_source_mappings = {
      bad = {
        event_source_arn  = "arn:aws:dynamodb:us-east-1:123456789012:table/test-orders/stream/2026-01-01T00:00:00.000"
        starting_position = "LATEST"
        scaling_config    = { maximum_concurrency = 5 }
      }
    }
  }

  expect_failures = [var.event_source_mappings]
}

run "rejects_maximum_concurrency_below_two" {
  command = plan

  variables {
    event_source_mappings = {
      bad = {
        event_source_arn = "arn:aws:sqs:us-east-1:123456789012:test-orders"
        scaling_config   = { maximum_concurrency = 1 }
      }
    }
  }

  expect_failures = [var.event_source_mappings]
}

run "rejects_a_fifo_batch_above_ten" {
  command = plan

  variables {
    event_source_mappings = {
      bad = {
        event_source_arn = "arn:aws:sqs:us-east-1:123456789012:test-orders.fifo"
        batch_size       = 11
      }
    }
  }

  expect_failures = [var.event_source_mappings]
}

run "rejects_a_kms_alias" {
  command = plan

  variables {
    event_source_mappings = {
      orders = { event_source_arn = "arn:aws:sqs:us-east-1:123456789012:test-orders" }
    }
    event_source_kms_key_arns = ["alias/aws/sqs"]
  }

  expect_failures = [var.event_source_kms_key_arns]
}

run "rejects_kms_keys_without_mappings" {
  command = plan

  variables {
    event_source_kms_key_arns = ["arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000"]
  }

  expect_failures = [var.event_source_kms_key_arns]
}

run "rejects_more_than_five_filter_patterns" {
  command = plan

  variables {
    event_source_mappings = {
      bad = {
        event_source_arn = "arn:aws:sqs:us-east-1:123456789012:test-orders"
        filter_criteria = {
          filter = [for i in range(6) : { pattern = jsonencode({ body = { n = [i] } }) }]
        }
      }
    }
  }

  expect_failures = [var.event_source_mappings]
}
