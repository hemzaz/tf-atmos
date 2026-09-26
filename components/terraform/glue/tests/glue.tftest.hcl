# Mock-provider tests: no AWS credentials, no network. Run from the component
# directory with `terraform init -backend=false && terraform test`. The role
# ARN is mocked to a fixed value so plan-only runs can assert crawlers/jobs
# use it; the data sources are overridden so ARNs built from them are real.

mock_provider "aws" {
  mock_resource "aws_glue_catalog_database" {
    override_during = plan
    defaults = {
      arn = "arn:aws:glue:eu-west-2:123456789012:database/test_data_lake"
    }
  }

  mock_resource "aws_iam_role" {
    override_during = plan
    defaults = {
      arn = "arn:aws:iam::123456789012:role/test-data-lake-glue"
    }
  }

  mock_resource "aws_glue_crawler" {
    override_during = plan
    defaults = {
      arn = "arn:aws:glue:eu-west-2:123456789012:crawler/mock"
    }
  }

  mock_resource "aws_glue_job" {
    override_during = plan
    defaults = {
      arn = "arn:aws:glue:eu-west-2:123456789012:job/mock"
    }
  }

  mock_resource "aws_glue_catalog_table" {
    override_during = plan
    defaults = {
      arn = "arn:aws:glue:eu-west-2:123456789012:table/test_data_lake/mock"
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
  region      = "eu-west-2"
  name        = "data-lake"
  kms_key_arn = "arn:aws:kms:eu-west-2:123456789012:key/00000000-0000-0000-0000-000000000000"
  tags = {
    Environment = "test"
    Tenant      = "fnx"
    ManagedBy   = "Terraform"
  }

  assets_bucket_name = "test-glue-assets"
  s3_read_buckets    = ["test-raw"]
  s3_write_buckets   = ["test-processed"]

  tables = {
    raw_events = {
      location              = "s3://test-raw/data/"
      input_format          = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
      output_format         = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
      parameters = {
        classification       = "parquet"
        "projection.enabled" = "true"
      }
      columns = [
        { name = "event_id", type = "string" },
      ]
      partition_keys = [
        { name = "year", type = "string" },
        { name = "month", type = "string" },
      ]
    }
  }

  crawlers = {
    raw_data = {
      catalog_tables = ["raw_events"]
      schema_change_policy = {
        delete_behavior = "LOG"
        update_behavior = "UPDATE_IN_DATABASE"
      }
    }
    curated_data = {
      schedule = "cron(0 0 * * ? *)"
      s3_targets = [
        { path = "s3://test-curated/" },
      ]
    }
  }

  jobs = {
    transformation = {
      script = "print('hello')"
    }
  }

  triggers = {
    after_transformation = {
      type = "CONDITIONAL"
      actions = [
        { crawler = "raw_data" },
      ]
      predicate = {
        conditions = [
          { job = "transformation", state = "SUCCEEDED" },
        ]
      }
    }
  }
}

run "names_follow_environment_name" {
  command = plan

  assert {
    condition     = aws_glue_catalog_database.this[0].name == "test_data_lake"
    error_message = "The database is <Environment>-<name> with hyphens replaced by underscores."
  }

  assert {
    condition     = aws_iam_role.this[0].name == "test-data-lake-glue"
    error_message = "The role is named <Environment>-<name>-glue."
  }

  assert {
    condition     = aws_glue_crawler.this["raw_data"].name == "test-data-lake-raw_data" && aws_glue_job.this["transformation"].name == "test-data-lake-transformation"
    error_message = "Crawlers and jobs are named <Environment>-<name>-<key>."
  }
}

run "security_configuration_encrypts_everything_with_the_key" {
  command = plan

  assert {
    condition = (
      aws_glue_security_configuration.this[0].encryption_configuration[0].cloudwatch_encryption[0].cloudwatch_encryption_mode == "SSE-KMS"
      && aws_glue_security_configuration.this[0].encryption_configuration[0].cloudwatch_encryption[0].kms_key_arn == var.kms_key_arn
      && aws_glue_security_configuration.this[0].encryption_configuration[0].job_bookmarks_encryption[0].job_bookmarks_encryption_mode == "CSE-KMS"
      && aws_glue_security_configuration.this[0].encryption_configuration[0].job_bookmarks_encryption[0].kms_key_arn == var.kms_key_arn
      && aws_glue_security_configuration.this[0].encryption_configuration[0].s3_encryption[0].s3_encryption_mode == "SSE-KMS"
      && aws_glue_security_configuration.this[0].encryption_configuration[0].s3_encryption[0].kms_key_arn == var.kms_key_arn
    )
    error_message = "CloudWatch Logs, job bookmarks and S3 output are all encrypted with kms_key_arn."
  }

  assert {
    condition     = aws_glue_crawler.this["raw_data"].security_configuration == "test-data-lake-security-config" && aws_glue_job.this["transformation"].security_configuration == "test-data-lake-security-config"
    error_message = "Every crawler and job uses the security configuration."
  }

  assert {
    condition     = aws_s3_object.script["transformation"].server_side_encryption == "aws:kms" && aws_s3_object.script["transformation"].kms_key_id == var.kms_key_arn
    error_message = "Job scripts are uploaded SSE-KMS with kms_key_arn."
  }
}

run "data_catalog_encryption_is_off_by_default" {
  command = plan

  assert {
    condition     = length(aws_glue_data_catalog_encryption_settings.this) == 0
    error_message = "The account-wide catalog encryption settings are only set when enable_data_catalog_encryption is true."
  }
}

run "data_catalog_encryption_uses_the_key_for_metadata_and_passwords" {
  command = plan

  variables {
    enable_data_catalog_encryption = true
  }

  assert {
    condition = (
      aws_glue_data_catalog_encryption_settings.this[0].data_catalog_encryption_settings[0].encryption_at_rest[0].catalog_encryption_mode == "SSE-KMS"
      && aws_glue_data_catalog_encryption_settings.this[0].data_catalog_encryption_settings[0].encryption_at_rest[0].sse_aws_kms_key_id == var.kms_key_arn
      && aws_glue_data_catalog_encryption_settings.this[0].data_catalog_encryption_settings[0].connection_password_encryption[0].return_connection_password_encrypted == true
      && aws_glue_data_catalog_encryption_settings.this[0].data_catalog_encryption_settings[0].connection_password_encryption[0].aws_kms_key_id == var.kms_key_arn
    )
    error_message = "Catalog metadata and connection passwords are encrypted with kms_key_arn."
  }
}

run "role_trust_is_glue_in_this_account" {
  command = plan

  assert {
    condition = (
      jsondecode(aws_iam_role.this[0].assume_role_policy).Statement[0].Principal.Service == "glue.amazonaws.com"
      && jsondecode(aws_iam_role.this[0].assume_role_policy).Statement[0].Condition.StringEquals["aws:SourceAccount"] == "123456789012"
    )
    error_message = "Only glue.amazonaws.com, acting for this account, can assume the role."
  }

  assert {
    condition     = aws_glue_crawler.this["raw_data"].role == "arn:aws:iam::123456789012:role/test-data-lake-glue" && aws_glue_job.this["transformation"].role_arn == "arn:aws:iam::123456789012:role/test-data-lake-glue"
    error_message = "Crawlers and jobs share the component's own role."
  }
}

run "catalog_and_logs_permissions_are_scoped" {
  command = plan

  assert {
    condition = one([for s in jsondecode(aws_iam_role_policy.service[0].policy).Statement : s if s.Sid == "AllowOwnCatalogDatabase"]).Resource == [
      "arn:aws:glue:eu-west-2:123456789012:catalog",
      "arn:aws:glue:eu-west-2:123456789012:database/test_data_lake",
      "arn:aws:glue:eu-west-2:123456789012:table/test_data_lake/*",
    ]
    error_message = "Catalog actions are limited to this instance's own database and its tables."
  }

  assert {
    condition = (
      one([for s in jsondecode(aws_iam_role_policy.service[0].policy).Statement : s if s.Sid == "AllowDefaultDatabaseLookup"]).Resource == "arn:aws:glue:eu-west-2:123456789012:database/default"
      && one([for s in jsondecode(aws_iam_role_policy.service[0].policy).Statement : s if s.Sid == "AllowDefaultDatabaseLookup"]).Action == "glue:GetDatabase"
    )
    error_message = "The default database is granted glue:GetDatabase only."
  }

  assert {
    condition     = one([for s in jsondecode(aws_iam_role_policy.service[0].policy).Statement : s if s.Sid == "AllowGlueLogGroups"]).Resource == "arn:aws:logs:eu-west-2:123456789012:log-group:/aws-glue/*"
    error_message = "Log group actions are limited to /aws-glue/*."
  }

  assert {
    condition     = one([for s in jsondecode(aws_iam_role_policy.service[0].policy).Statement : s if s.Sid == "AllowGlueMetrics"]).Condition.StringEquals["cloudwatch:namespace"] == "Glue"
    error_message = "PutMetricData (no resource ARN) is limited to the Glue namespace."
  }

  assert {
    condition     = length([for s in jsondecode(aws_iam_role_policy.service[0].policy).Statement : s if s.Resource == "*" && s.Sid != "AllowGlueMetrics"]) == 0
    error_message = "Only the namespace-conditioned metrics statement uses a wildcard resource."
  }
}

run "kms_grant_is_scoped_to_the_key" {
  command = plan

  assert {
    condition     = jsondecode(aws_iam_role_policy.kms[0].policy).Statement[0].Resource == var.kms_key_arn
    error_message = "The role's KMS grant is limited to kms_key_arn."
  }
}

run "s3_permissions_are_scoped_to_derived_and_declared_buckets" {
  command = plan

  assert {
    condition     = toset(one([for s in jsondecode(aws_iam_role_policy.s3[0].policy).Statement : s if s.Sid == "AllowReadObjects"]).Resource) == toset(["arn:aws:s3:::test-curated/*", "arn:aws:s3:::test-raw/*"])
    error_message = "Read covers crawler s3_targets buckets, table-location buckets and s3_read_buckets (deduplicated)."
  }

  assert {
    condition     = one([for s in jsondecode(aws_iam_role_policy.s3[0].policy).Statement : s if s.Sid == "AllowWriteObjects"]).Resource == ["arn:aws:s3:::test-processed/*"]
    error_message = "Write covers only s3_write_buckets."
  }

  assert {
    condition     = one([for s in jsondecode(aws_iam_role_policy.s3[0].policy).Statement : s if s.Sid == "AllowReadOwnScripts"]).Resource == "arn:aws:s3:::test-glue-assets/scripts/test-data-lake/*"
    error_message = "Script read is limited to this instance's own script prefix."
  }

  assert {
    condition     = one([for s in jsondecode(aws_iam_role_policy.s3[0].policy).Statement : s if s.Sid == "AllowOwnTemporaryPrefix"]).Resource == "arn:aws:s3:::test-glue-assets/temporary/test-data-lake/*"
    error_message = "Temporary read/write is limited to this instance's own temporary prefix."
  }
}

run "jobs_upload_their_script_and_get_default_arguments" {
  command = plan

  assert {
    condition     = aws_s3_object.script["transformation"].bucket == "test-glue-assets" && aws_s3_object.script["transformation"].key == "scripts/test-data-lake/transformation.py"
    error_message = "The script is uploaded to scripts/<Environment>-<name>/<key>.py in assets_bucket_name."
  }

  assert {
    condition     = aws_glue_job.this["transformation"].command[0].script_location == "s3://test-glue-assets/scripts/test-data-lake/transformation.py"
    error_message = "The job runs the uploaded script."
  }

  assert {
    condition = (
      aws_glue_job.this["transformation"].default_arguments["--TempDir"] == "s3://test-glue-assets/temporary/test-data-lake/"
      && aws_glue_job.this["transformation"].default_arguments["--enable-glue-datacatalog"] == "true"
      && aws_glue_job.this["transformation"].default_arguments["--job-bookmark-option"] == "job-bookmark-enable"
    )
    error_message = "Jobs get the component's default arguments."
  }
}

run "tables_derive_a_projection_location_template" {
  command = plan

  assert {
    condition     = aws_glue_catalog_table.this["raw_events"].parameters["storage.location.template"] == "s3://test-raw/data/year=$${year}/month=$${month}/"
    error_message = "A projected table gets <location><key>=$${<key>}/ for each partition key."
  }

  assert {
    condition     = length(aws_glue_catalog_table.this["raw_events"].partition_keys) == 2
    error_message = "Partition keys are passed through."
  }
}

run "crawlers_target_s3_or_catalog_tables" {
  command = plan

  assert {
    condition     = length(aws_glue_crawler.this["raw_data"].catalog_target) == 1 && aws_glue_crawler.this["raw_data"].catalog_target[0].tables == tolist(["raw_events"])
    error_message = "catalog_tables becomes one catalog_target over the instance's own tables."
  }

  assert {
    condition     = length(aws_glue_crawler.this["curated_data"].s3_target) == 1 && length(aws_glue_crawler.this["curated_data"].catalog_target) == 0
    error_message = "s3_targets become s3_target blocks."
  }
}

run "triggers_resolve_job_and_crawler_keys" {
  command = plan

  assert {
    condition     = aws_glue_trigger.this["after_transformation"].actions[0].crawler_name == "test-data-lake-raw_data"
    error_message = "A trigger action's crawler key resolves to the crawler name."
  }

  assert {
    condition = (
      aws_glue_trigger.this["after_transformation"].predicate[0].conditions[0].job_name == "test-data-lake-transformation"
      && aws_glue_trigger.this["after_transformation"].predicate[0].conditions[0].state == "SUCCEEDED"
    )
    error_message = "A predicate condition's job key resolves to the job name and keeps its state."
  }
}

run "rejects_a_crawler_with_both_target_kinds" {
  command = plan

  variables {
    crawlers = {
      both = {
        s3_targets     = [{ path = "s3://test-raw/" }]
        catalog_tables = ["raw_events"]
        schema_change_policy = {
          delete_behavior = "LOG"
          update_behavior = "LOG"
        }
      }
    }
    triggers = {}
  }

  expect_failures = [var.crawlers]
}

run "rejects_a_catalog_crawler_that_deletes" {
  command = plan

  variables {
    crawlers = {
      raw_data = {
        catalog_tables = ["raw_events"]
        schema_change_policy = {
          delete_behavior = "DELETE_FROM_DATABASE"
          update_behavior = "UPDATE_IN_DATABASE"
        }
      }
    }
  }

  expect_failures = [var.crawlers]
}

run "rejects_jobs_without_an_assets_bucket" {
  command = plan

  variables {
    assets_bucket_name = ""
  }

  expect_failures = [var.jobs]
}

run "rejects_a_trigger_referencing_an_unknown_job" {
  command = plan

  variables {
    triggers = {
      bad = {
        type    = "ON_DEMAND"
        actions = [{ job = "does_not_exist" }]
      }
    }
  }

  expect_failures = [var.triggers]
}

run "rejects_a_scheduled_trigger_without_a_schedule" {
  command = plan

  variables {
    triggers = {
      bad = {
        type    = "SCHEDULED"
        actions = [{ job = "transformation" }]
      }
    }
  }

  expect_failures = [var.triggers]
}

run "rejects_an_invalid_kms_key_arn" {
  command = plan

  variables {
    kms_key_arn = "alias/main"
  }

  expect_failures = [var.kms_key_arn]
}

run "disabled_creates_nothing" {
  command = plan

  variables {
    enabled = false
  }

  assert {
    condition = (
      length(aws_glue_catalog_database.this) == 0
      && length(aws_glue_catalog_table.this) == 0
      && length(aws_iam_role.this) == 0
      && length(aws_glue_security_configuration.this) == 0
      && length(aws_glue_crawler.this) == 0
      && length(aws_glue_job.this) == 0
      && length(aws_s3_object.script) == 0
      && length(aws_glue_trigger.this) == 0
    )
    error_message = "enabled = false creates nothing."
  }

  assert {
    condition     = output.database_name == null && output.role_arn == null && output.job_names == {}
    error_message = "Outputs are null/empty when disabled."
  }
}
