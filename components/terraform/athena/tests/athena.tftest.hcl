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

override_data {
  target = data.aws_partition.current
  values = {
    partition = "aws"
  }
}

override_data {
  target = data.aws_caller_identity.current
  values = {
    account_id = "123456789012"
  }
}

override_data {
  target = data.aws_region.current
  values = {
    region = "eu-west-2"
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

  assert {
    condition     = aws_athena_workgroup.this[0].configuration[0].result_configuration[0].expected_bucket_owner == "123456789012"
    error_message = "Results are only written to a bucket owned by this account."
  }
}

run "workgroup_configuration_is_always_enforced" {
  command = plan

  assert {
    condition     = aws_athena_workgroup.this[0].configuration[0].enforce_workgroup_configuration == true
    error_message = "enforce_workgroup_configuration is always true, so clients cannot override output location or encryption."
  }
}

run "query_policy_is_scoped_to_the_workgroup_results_bucket_and_key" {
  command = plan

  assert {
    condition     = one([for s in jsondecode(output.query_policy).Statement : s if s.Sid == "AllowWorkgroupQueries"]).Resource == "arn:aws:athena:eu-west-2:123456789012:workgroup/test-data-pipeline"
    error_message = "Athena actions are scoped to this workgroup's ARN."
  }

  assert {
    condition     = one([for s in jsondecode(output.query_policy).Statement : s if s.Sid == "AllowResultsBucket"]).Resource == "arn:aws:s3:::test-athena-results"
    error_message = "Bucket-level S3 actions are scoped to the results bucket parsed from output_location."
  }

  assert {
    condition     = one([for s in jsondecode(output.query_policy).Statement : s if s.Sid == "AllowResultsObjects"]).Resource == "arn:aws:s3:::test-athena-results/*"
    error_message = "Object-level S3 actions are scoped to the results bucket's objects."
  }

  assert {
    condition     = one([for s in jsondecode(output.query_policy).Statement : s if s.Sid == "AllowResultsKMS"]).Resource == var.kms_key_arn
    error_message = "KMS actions are scoped to kms_key_arn."
  }

  assert {
    condition     = alltrue([for s in jsondecode(output.query_policy).Statement : s.Resource != "*"])
    error_message = "No query_policy statement uses a wildcard resource."
  }

  assert {
    condition     = length([for s in jsondecode(output.query_policy).Statement : s if s.Sid == "AllowCatalogRead" || s.Sid == "AllowReadSourceObjects"]) == 0
    error_message = "Catalog and source-data statements are omitted when query_database_names/query_source_buckets are empty."
  }
}

run "query_policy_adds_catalog_and_source_reads_when_given" {
  command = plan

  variables {
    query_database_names = ["test_data_lake"]
    query_source_buckets = ["test-data-lake-processed"]
  }

  assert {
    condition = one([for s in jsondecode(output.query_policy).Statement : s if s.Sid == "AllowCatalogRead"]).Resource == [
      "arn:aws:glue:eu-west-2:123456789012:catalog",
      "arn:aws:glue:eu-west-2:123456789012:database/test_data_lake",
      "arn:aws:glue:eu-west-2:123456789012:table/test_data_lake/*",
    ]
    error_message = "Catalog read is scoped to the catalog, the named databases and their tables."
  }

  assert {
    condition     = one([for s in jsondecode(output.query_policy).Statement : s if s.Sid == "AllowReadSourceObjects"]).Resource == ["arn:aws:s3:::test-data-lake-processed/*"]
    error_message = "Source-data read is scoped to query_source_buckets."
  }
}

run "data_catalogs_create_one_catalog_per_key" {
  command = plan

  variables {
    data_catalogs = {
      shared = {
        type       = "GLUE"
        parameters = { "catalog-id" = "210987654321" }
      }
    }
  }

  assert {
    condition     = aws_athena_data_catalog.this["shared"].name == "test-data-pipeline-shared" && aws_athena_data_catalog.this["shared"].type == "GLUE"
    error_message = "A data catalog is named <Environment>-<name>-<key> with the given type."
  }

  assert {
    condition     = output.data_catalog_names == { shared = "test-data-pipeline-shared" }
    error_message = "data_catalog_names maps key to name."
  }
}

run "rejects_a_glue_data_catalog_without_a_catalog_id" {
  command = plan

  variables {
    data_catalogs = {
      shared = {
        type       = "GLUE"
        parameters = {}
      }
    }
  }

  expect_failures = [var.data_catalogs]
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

  assert {
    condition     = output.query_policy == null && output.results_bucket_name == null && length(aws_athena_data_catalog.this) == 0
    error_message = "query_policy/results_bucket_name are null and no data catalog is created when disabled."
  }
}
