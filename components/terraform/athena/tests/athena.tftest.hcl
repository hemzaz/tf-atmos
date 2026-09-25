# Mock-provider tests: no AWS credentials, no network. Run from the component
# directory with `terraform init -backend=false && terraform test`.

mock_provider "aws" {
  mock_resource "aws_athena_workgroup" {
    defaults = {
      arn  = "arn:aws:athena:eu-west-2:123456789012:workgroup/test-data-pipeline"
      name = "test-data-pipeline"
    }
  }

  mock_resource "aws_athena_named_query" {
    defaults = {
      id = "00000000-0000-0000-0000-000000000000"
    }
  }
}

variables {
  region          = "eu-west-2"
  name            = "data-pipeline"
  output_location = "s3://test-athena-results/"
  kms_key_arn     = "arn:aws:kms:eu-west-2:123456789012:key/00000000-0000-0000-0000-000000000000"
  tags = {
    Environment = "test"
    Tenant      = "fnx"
    ManagedBy   = "Terraform"
  }
}

run "the_workgroup_is_named_environment_name" {
  command = plan

  assert {
    condition     = aws_athena_workgroup.this[0].name == "test-data-pipeline"
    error_message = "The workgroup is named <Environment>-<name>."
  }
}

run "result_encryption_is_always_sse_kms" {
  command = plan

  assert {
    condition     = aws_athena_workgroup.this[0].configuration[0].result_configuration[0].encryption_configuration[0].encryption_option == "SSE_KMS"
    error_message = "encryption_option is always SSE_KMS; there is no unencrypted option."
  }

  assert {
    condition     = aws_athena_workgroup.this[0].configuration[0].result_configuration[0].encryption_configuration[0].kms_key_arn == var.kms_key_arn
    error_message = "kms_key_arn is passed through."
  }

  assert {
    condition     = aws_athena_workgroup.this[0].configuration[0].result_configuration[0].output_location == "s3://test-athena-results/"
    error_message = "output_location is passed through."
  }
}

run "bytes_scanned_cutoff_is_applied" {
  command = plan

  variables {
    bytes_scanned_cutoff_per_query = 10737418240
  }

  assert {
    condition     = aws_athena_workgroup.this[0].configuration[0].bytes_scanned_cutoff_per_query == 10737418240
    error_message = "bytes_scanned_cutoff_per_query is passed through."
  }
}

run "bytes_scanned_cutoff_defaults_to_unset" {
  command = plan

  assert {
    condition     = aws_athena_workgroup.this[0].configuration[0].bytes_scanned_cutoff_per_query == null
    error_message = "bytes_scanned_cutoff_per_query defaults to null (no cutoff)."
  }
}

run "rejects_a_cutoff_below_the_aws_minimum" {
  command = plan

  variables {
    bytes_scanned_cutoff_per_query = 1024
  }

  expect_failures = [var.bytes_scanned_cutoff_per_query]
}

run "enforce_and_publish_metrics_default_to_true" {
  command = plan

  assert {
    condition     = aws_athena_workgroup.this[0].configuration[0].enforce_workgroup_configuration == true
    error_message = "enforce_workgroup_configuration defaults to true."
  }

  assert {
    condition     = aws_athena_workgroup.this[0].configuration[0].publish_cloudwatch_metrics_enabled == true
    error_message = "publish_cloudwatch_metrics_enabled defaults to true."
  }
}

run "engine_version_is_passed_through" {
  command = plan

  assert {
    condition     = aws_athena_workgroup.this[0].configuration[0].engine_version[0].selected_engine_version == "Athena engine version 3"
    error_message = "engine_version defaults to Athena engine version 3 and is passed through as selected_engine_version."
  }
}

run "named_queries_create_a_named_query_per_key_against_the_workgroup" {
  command = plan

  variables {
    named_queries = {
      daily_summary = {
        database    = "test_data_lake"
        query       = "SELECT 1"
        description = "Daily Summary"
      }
      error_analysis = {
        database = "test_data_lake"
        query    = "SELECT 2"
      }
    }
  }

  assert {
    condition     = length(aws_athena_named_query.this) == 2
    error_message = "One aws_athena_named_query per named_queries entry."
  }

  assert {
    condition     = aws_athena_named_query.this["daily_summary"].name == "test-data-pipeline-daily_summary"
    error_message = "A named query is named <Environment>-<name>-<named_queries key>."
  }

  assert {
    condition     = aws_athena_named_query.this["daily_summary"].database == "test_data_lake"
    error_message = "database is passed through."
  }

  assert {
    condition     = aws_athena_named_query.this["daily_summary"].workgroup == "test-data-pipeline"
    error_message = "Every named query runs against this instance's own workgroup."
  }

  assert {
    condition     = aws_athena_named_query.this["error_analysis"].description == null
    error_message = "description defaults to unset when omitted."
  }
}

run "rejects_an_output_location_that_is_not_an_s3_uri" {
  command = plan

  variables {
    output_location = "https://example.com/bucket/"
  }

  expect_failures = [var.output_location]
}

run "rejects_an_invalid_name" {
  command = plan

  variables {
    name = "Data_Pipeline"
  }

  expect_failures = [var.name]
}

run "rejects_an_empty_kms_key_arn" {
  command = plan

  variables {
    kms_key_arn = ""
  }

  expect_failures = [var.kms_key_arn]
}

run "disabled_creates_nothing" {
  command = plan

  variables {
    enabled = false
    named_queries = {
      daily_summary = {
        database = "test_data_lake"
        query    = "SELECT 1"
      }
    }
  }

  assert {
    condition     = length(aws_athena_workgroup.this) == 0 && length(aws_athena_named_query.this) == 0
    error_message = "enabled = false must create nothing, including any named queries."
  }

  assert {
    condition     = output.workgroup_name == null && output.workgroup_arn == null
    error_message = "Outputs are null when disabled."
  }

  assert {
    condition     = output.named_query_ids == {}
    error_message = "named_query_ids is an empty map when disabled."
  }
}
