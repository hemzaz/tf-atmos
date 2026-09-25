# Mock-provider tests: no AWS credentials, no network. Run from the component
# directory with `terraform init -backend=false && terraform test`. IAM role
# arn is mocked to a fixed, valid-looking value (as in this repo's
# stepfunctions tests) so plan-only runs can assert a crawler's `role`
# equals it. data.aws_partition is overridden too: a mock provider's default
# fake value for it fails aws_iam_role_policy_attachment.policy_arn's ARN
# format validation (the policy ARN is built from it), even under mocking.
mock_provider "aws" {
  mock_resource "aws_glue_catalog_database" {
    defaults = {
      arn = "arn:aws:glue:eu-west-2:123456789012:database/test_data_lake"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/mock"
    }
  }

  mock_resource "aws_glue_security_configuration" {
    defaults = {
      id = "test-data-lake-security-config"
    }
  }

  mock_resource "aws_glue_crawler" {
    defaults = {
      arn = "arn:aws:glue:eu-west-2:123456789012:crawler/test-data-lake-raw_data"
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

variables {
  region      = "eu-west-2"
  name        = "data-lake"
  kms_key_arn = "arn:aws:kms:eu-west-2:123456789012:key/00000000-0000-0000-0000-000000000000"
  tags = {
    Environment = "test"
    Tenant      = "fnx"
    ManagedBy   = "Terraform"
  }
  crawlers = {
    raw_data = {
      schedule = "cron(0 */6 * * ? *)"
      s3_targets = [
        {
          path       = "s3://test-raw-bucket/data/"
          exclusions = ["errors/**"]
        }
      ]
      schema_change_policy = {
        delete_behavior = "LOG"
        update_behavior = "UPDATE_IN_DATABASE"
      }
      table_prefix = "raw_"
    }
    processed_data = {
      s3_targets = [
        { path = "s3://test-processed-bucket/data/" }
      ]
    }
  }
}

run "database_name_is_environment_name_with_hyphens_replaced_by_underscores" {
  command = plan

  assert {
    condition     = aws_glue_catalog_database.this[0].name == "test_data_lake"
    error_message = "The database is named <Environment>-<name> with hyphens replaced by underscores."
  }
}

run "location_uri_and_description_are_passed_through" {
  command = plan

  variables {
    location_uri          = "s3://test-curated-bucket/"
    database_description  = "Data lake catalog database"
  }

  assert {
    condition     = aws_glue_catalog_database.this[0].location_uri == "s3://test-curated-bucket/"
    error_message = "location_uri is passed through."
  }

  assert {
    condition     = aws_glue_catalog_database.this[0].description == "Data lake catalog database"
    error_message = "database_description is passed through."
  }
}

run "create_table_default_permissions_becomes_a_permission_block" {
  command = plan

  variables {
    create_table_default_permissions = [{
      principal   = { data_lake_principal_identifier = "IAM_ALLOWED_PRINCIPALS" }
      permissions = ["ALL"]
    }]
  }

  assert {
    condition     = aws_glue_catalog_database.this[0].create_table_default_permission[0].principal[0].data_lake_principal_identifier == "IAM_ALLOWED_PRINCIPALS"
    error_message = "create_table_default_permissions.principal is passed through."
  }

  assert {
    condition     = aws_glue_catalog_database.this[0].create_table_default_permission[0].permissions == toset(["ALL"])
    error_message = "create_table_default_permissions.permissions is passed through."
  }
}

run "every_crawler_creates_an_aws_glue_crawler_named_after_its_key" {
  command = plan

  assert {
    condition     = length(aws_glue_crawler.this) == 2
    error_message = "One aws_glue_crawler per crawlers entry."
  }

  assert {
    condition     = aws_glue_crawler.this["raw_data"].name == "test-data-lake-raw_data"
    error_message = "A crawler is named <Environment>-<name>-<crawlers key>."
  }

  assert {
    condition     = aws_glue_crawler.this["raw_data"].database_name == "test_data_lake"
    error_message = "Every crawler targets this instance's own catalog database."
  }

  assert {
    condition     = aws_glue_crawler.this["raw_data"].table_prefix == "raw_"
    error_message = "table_prefix is passed through."
  }

  assert {
    condition     = toset(aws_glue_crawler.this["raw_data"].s3_target[0].exclusions) == toset(["errors/**"])
    error_message = "s3_targets.exclusions is passed through."
  }

  assert {
    condition     = aws_glue_crawler.this["raw_data"].schema_change_policy[0].delete_behavior == "LOG"
    error_message = "schema_change_policy is passed through."
  }
}

run "every_crawler_shares_the_one_component_created_role_and_security_configuration" {
  # role compares two Computed-only (mocked) attributes to each other,
  # which is unknown until apply even under mock_provider - apply here runs
  # against the mock, not real AWS.
  command = apply

  assert {
    condition     = aws_glue_crawler.this["raw_data"].role == aws_iam_role.crawler[0].arn
    error_message = "Every crawler uses the component-created crawler role."
  }

  assert {
    condition     = aws_glue_crawler.this["processed_data"].role == aws_iam_role.crawler[0].arn
    error_message = "Every crawler uses the same crawler role, not one each."
  }

  assert {
    condition     = aws_glue_crawler.this["raw_data"].security_configuration == aws_glue_security_configuration.this[0].name
    error_message = "Every crawler uses the component-created security configuration."
  }
}

run "the_crawler_role_attaches_the_aws_managed_glue_service_role_policy" {
  command = plan

  assert {
    condition     = aws_iam_role_policy_attachment.glue_service_role[0].policy_arn == "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
    error_message = "The crawler role attaches the AWS managed AWSGlueServiceRole policy."
  }
}

run "the_crawler_role_s3_policy_is_scoped_to_exactly_the_target_buckets" {
  command = plan

  assert {
    condition     = length(aws_iam_role_policy.crawler_s3) == 1
    error_message = "An S3 policy is created when crawlers have s3_targets."
  }

  assert {
    # toset() on both sides: order-independent (map iteration order is by
    # sorted key, "processed_data" before "raw_data", not declaration
    # order), and sidesteps jsondecode()'s tuple type vs a list literal's
    # list type showing up as "different types" in a direct == compare.
    condition = toset(jsondecode(aws_iam_role_policy.crawler_s3[0].policy).Statement[0].Resource) == toset([
      "arn:aws:s3:::test-raw-bucket",
      "arn:aws:s3:::test-processed-bucket",
    ])
    error_message = "s3:ListBucket is scoped to exactly the buckets derived from every crawler's s3_targets, deduplicated - not a wildcard."
  }

  assert {
    condition = toset(jsondecode(aws_iam_role_policy.crawler_s3[0].policy).Statement[1].Resource) == toset([
      "arn:aws:s3:::test-raw-bucket/*",
      "arn:aws:s3:::test-processed-bucket/*",
    ])
    error_message = "s3:GetObject is scoped to the objects in exactly those same target buckets."
  }
}

run "the_crawler_role_kms_policy_grants_decrypt_encrypt_and_generate_data_key_on_the_key" {
  command = plan

  assert {
    condition     = jsondecode(aws_iam_role_policy.crawler_kms[0].policy).Statement[0].Resource == var.kms_key_arn
    error_message = "The KMS grant is scoped to kms_key_arn."
  }

  assert {
    condition     = toset(jsondecode(aws_iam_role_policy.crawler_kms[0].policy).Statement[0].Action) == toset(["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey"])
    error_message = "The crawler role can decrypt source data and encrypt/decrypt its own CloudWatch Logs, job bookmark and S3 output via the security configuration."
  }
}

run "the_security_configuration_uses_sse_kms_everywhere" {
  command = plan

  assert {
    condition     = aws_glue_security_configuration.this[0].encryption_configuration[0].cloudwatch_encryption[0].cloudwatch_encryption_mode == "SSE-KMS"
    error_message = "CloudWatch Logs encryption is SSE-KMS."
  }

  assert {
    condition     = aws_glue_security_configuration.this[0].encryption_configuration[0].cloudwatch_encryption[0].kms_key_arn == var.kms_key_arn
    error_message = "CloudWatch Logs encryption uses kms_key_arn."
  }

  assert {
    condition     = aws_glue_security_configuration.this[0].encryption_configuration[0].job_bookmarks_encryption[0].job_bookmarks_encryption_mode == "CSE-KMS"
    error_message = "Job bookmark encryption is CSE-KMS."
  }

  assert {
    condition     = aws_glue_security_configuration.this[0].encryption_configuration[0].s3_encryption[0].s3_encryption_mode == "SSE-KMS"
    error_message = "Crawler S3 output encryption is SSE-KMS."
  }

  assert {
    condition     = aws_glue_security_configuration.this[0].encryption_configuration[0].s3_encryption[0].kms_key_arn == var.kms_key_arn
    error_message = "S3 output encryption uses kms_key_arn."
  }
}

run "rejects_a_crawler_with_no_s3_targets" {
  command = plan

  variables {
    crawlers = {
      empty = {
        s3_targets = []
      }
    }
  }

  expect_failures = [var.crawlers]
}

run "rejects_an_invalid_schema_change_policy" {
  command = plan

  variables {
    crawlers = {
      raw_data = {
        s3_targets = [{ path = "s3://test-raw-bucket/data/" }]
        schema_change_policy = {
          delete_behavior = "NOT_A_REAL_BEHAVIOR"
          update_behavior = "UPDATE_IN_DATABASE"
        }
      }
    }
  }

  expect_failures = [var.crawlers]
}

run "rejects_an_invalid_name" {
  command = plan

  variables {
    name = "Data_Lake"
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
  }

  assert {
    condition     = length(aws_glue_catalog_database.this) == 0 && length(aws_glue_crawler.this) == 0 && length(aws_iam_role.crawler) == 0 && length(aws_glue_security_configuration.this) == 0
    error_message = "enabled = false must create nothing."
  }

  assert {
    condition     = output.database_name == null && output.database_arn == null && output.role_arn == null && output.security_configuration_name == null
    error_message = "Outputs are null when disabled."
  }

  assert {
    condition     = output.crawler_names == {} && output.crawler_arns == {}
    error_message = "crawler_names and crawler_arns are empty maps when disabled."
  }
}
