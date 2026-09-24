# Offline tests: the real AWS provider with dummy credentials, as in
# kms/tests. aws_iam_policy_document is computed locally, so the bucket policy
# can be asserted; a mock provider would return a random string for it. Every
# check that would call AWS is skipped and caller identity is overridden, so
# nothing reaches AWS (all runs are plans).
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
  name        = "assets"
  kms_key_arn = "arn:aws:kms:eu-west-2:123456789012:key/00000000-0000-0000-0000-000000000000"
  tags = {
    Environment = "test"
    Tenant      = "fnx"
    ManagedBy   = "Terraform"
  }
}

run "security_defaults" {
  command = plan

  assert {
    condition     = aws_s3_bucket.this[0].bucket == "test-assets-123456789012" && aws_s3_bucket.this[0].force_destroy == false
    error_message = "The bucket is <Environment>-<name>-<account id> and not force-destroyed."
  }

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.this[0].block_public_acls,
      aws_s3_bucket_public_access_block.this[0].block_public_policy,
      aws_s3_bucket_public_access_block.this[0].ignore_public_acls,
      aws_s3_bucket_public_access_block.this[0].restrict_public_buckets,
    ])
    error_message = "All public access is blocked."
  }

  assert {
    condition     = one(aws_s3_bucket_ownership_controls.this[0].rule).object_ownership == "BucketOwnerEnforced"
    error_message = "Object ownership is enforced (ACLs disabled)."
  }

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.this[0].rule).apply_server_side_encryption_by_default).sse_algorithm == "aws:kms" && one(one(aws_s3_bucket_server_side_encryption_configuration.this[0].rule).apply_server_side_encryption_by_default).kms_master_key_id == var.kms_key_arn
    error_message = "Default encryption is SSE-KMS with the given CMK."
  }

  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.this[0].rule).bucket_key_enabled == true
    error_message = "A bucket key is used by default."
  }

  assert {
    condition     = one(aws_s3_bucket_versioning.this[0].versioning_configuration).status == "Enabled"
    error_message = "Versioning is on by default."
  }

  assert {
    condition     = length(aws_s3_bucket_logging.this) == 0 && length(aws_s3_bucket_lifecycle_configuration.this) == 0
    error_message = "No access logging or lifecycle rules unless configured."
  }
}

run "bucket_policy_denies_requests_without_tls" {
  command = plan

  assert {
    condition     = one(jsondecode(data.aws_iam_policy_document.bucket[0].json).Statement).Effect == "Deny" && one(jsondecode(data.aws_iam_policy_document.bucket[0].json).Statement).Action == "s3:*"
    error_message = "The policy denies every S3 action..."
  }

  assert {
    condition     = one(jsondecode(data.aws_iam_policy_document.bucket[0].json).Statement).Condition.Bool["aws:SecureTransport"] == "false"
    error_message = "...on requests without TLS (aws:SecureTransport = false)."
  }

  assert {
    condition     = toset(one(jsondecode(data.aws_iam_policy_document.bucket[0].json).Statement).Resource) == toset(["arn:aws:s3:::test-assets-123456789012", "arn:aws:s3:::test-assets-123456789012/*"])
    error_message = "The deny covers the bucket and its objects."
  }

  assert {
    condition     = length(aws_s3_bucket_policy.this) == 1
    error_message = "The policy is attached."
  }
}

run "source_policies_are_merged_with_the_tls_statement" {
  command = plan

  variables {
    source_policy_documents = [jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Sid       = "AllowCloudFrontRead"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = "arn:aws:s3:::test-assets-123456789012/*"
      }]
    })]
  }

  assert {
    condition     = toset([for s in jsondecode(data.aws_iam_policy_document.bucket[0].json).Statement : s.Sid]) == toset(["AllowCloudFrontRead", "ForceSSLOnlyAccess"])
    error_message = "Caller statements are kept alongside ForceSSLOnlyAccess."
  }
}

run "logging_and_lifecycle_rules" {
  command = plan

  variables {
    bucket_name        = "fnx-test-assets"
    versioning_enabled = false
    logging = {
      bucket_name = "fnx-test-access-logs"
      prefix      = "assets/"
    }
    lifecycle_configuration_rules = [
      {
        id                                     = "all"
        abort_incomplete_multipart_upload_days = 7
        noncurrent_version_expiration          = { noncurrent_days = 30 }
        transition                             = [{ days = 90, storage_class = "STANDARD_IA" }]
      },
      {
        id         = "tmp"
        filter_and = { prefix = "tmp/" }
        expiration = { days = 1 }
      },
      {
        id         = "big-logs"
        filter_and = { prefix = "logs/", object_size_greater_than = 1048576 }
        expiration = { days = 30 }
      },
    ]
  }

  assert {
    condition     = aws_s3_bucket.this[0].bucket == "fnx-test-assets" && one(aws_s3_bucket_versioning.this[0].versioning_configuration).status == "Suspended"
    error_message = "bucket_name overrides the generated name; versioning can be suspended."
  }

  assert {
    condition     = aws_s3_bucket_logging.this[0].target_bucket == "fnx-test-access-logs" && aws_s3_bucket_logging.this[0].target_prefix == "assets/"
    error_message = "Access logs go to the given bucket and prefix."
  }

  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.this[0].rule) == 3 && aws_s3_bucket_lifecycle_configuration.this[0].rule[0].status == "Enabled"
    error_message = "One lifecycle rule per entry, enabled by default."
  }

  assert {
    condition     = one(aws_s3_bucket_lifecycle_configuration.this[0].rule[0].abort_incomplete_multipart_upload).days_after_initiation == 7 && one(aws_s3_bucket_lifecycle_configuration.this[0].rule[0].transition).storage_class == "STANDARD_IA"
    error_message = "Rule settings are passed through."
  }

  assert {
    condition     = one(aws_s3_bucket_lifecycle_configuration.this[0].rule[1].filter).prefix == "tmp/" && length(one(aws_s3_bucket_lifecycle_configuration.this[0].rule[1].filter).and) == 0
    error_message = "A prefix-only filter is sent without `and` (Cloud Posse's workaround)."
  }

  assert {
    condition     = one(one(aws_s3_bucket_lifecycle_configuration.this[0].rule[2].filter).and).object_size_greater_than == 1048576
    error_message = "A multi-criteria filter uses `and`."
  }
}

run "disabled_creates_nothing" {
  command = plan

  variables {
    enabled = false
  }

  assert {
    condition     = length(aws_s3_bucket.this) == 0 && length(aws_s3_bucket_policy.this) == 0
    error_message = "enabled = false must create nothing."
  }

  assert {
    condition     = output.bucket_arn == null && output.bucket_regional_domain_name == null
    error_message = "Outputs are null when disabled."
  }
}

run "rejects_a_non_kms_key" {
  command = plan

  variables {
    kms_key_arn = "alias/aws/s3"
  }

  expect_failures = [var.kms_key_arn]
}

run "rejects_an_invalid_bucket_name" {
  command = plan

  variables {
    bucket_name = "Not_A_Bucket"
  }

  expect_failures = [var.bucket_name]
}

run "rejects_an_unknown_storage_class" {
  command = plan

  variables {
    lifecycle_configuration_rules = [{ id = "x", transition = [{ days = 30, storage_class = "COLD" }] }]
  }

  expect_failures = [var.lifecycle_configuration_rules]
}

run "rejects_a_generated_name_over_63_characters" {
  command = plan

  variables {
    name = "a-thirty-character-bucket-name"
    tags = {
      Environment = "an-environment-name-that-is-long"
      ManagedBy   = "Terraform"
    }
  }

  expect_failures = [aws_s3_bucket.this[0]]
}
