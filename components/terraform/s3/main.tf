# One S3 bucket per instance, modelled on Cloud Posse's aws-s3-bucket
# component (which wraps cloudposse/s3-bucket). Written as plain resources,
# like the other root components. Security settings Cloud Posse leaves as
# inputs are fixed here: SSE-KMS with a customer managed key, all public
# access blocked, ACLs disabled (BucketOwnerEnforced) and a TLS-only bucket
# policy.

locals {
  enabled = var.enabled

  account_id  = data.aws_caller_identity.current.account_id
  bucket_name = var.bucket_name != "" ? var.bucket_name : "${var.tags["Environment"]}-${var.name}-${local.account_id}"
  # Built from the name, not aws_s3_bucket.this.arn, so the bucket policy is
  # fully known at plan time (and so reviewable in the plan).
  bucket_arn = "arn:${data.aws_partition.current.partition}:s3:::${local.bucket_name}"

  # Cloud Posse's lifecycle.tf: a filter is always sent; a prefix-only
  # filter must not use `and` (hashicorp/terraform-provider-aws#23882).
  lifecycle_rules = [for r in var.lifecycle_configuration_rules : merge(r, {
    filter_prefix_only = try(r.filter_and.prefix != null && r.filter_and.object_size_greater_than == null && r.filter_and.object_size_less_than == null && length(r.filter_and.tags) == 0, false) ? r.filter_and.prefix : null
  })]
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

resource "aws_s3_bucket" "this" {
  #checkov:skip=CKV2_AWS_6:False positive, aws_s3_bucket_public_access_block.this covers this bucket via count
  #checkov:skip=CKV_AWS_21:False positive, aws_s3_bucket_versioning.this covers this bucket via count
  #checkov:skip=CKV_AWS_145:False positive, aws_s3_bucket_server_side_encryption_configuration.this uses the kms_key_arn CMK
  #checkov:skip=CKV2_AWS_61:Lifecycle rules are an input (lifecycle_configuration_rules), set per instance
  #checkov:skip=CKV_AWS_18:Access logging is an input (logging); the target must be an SSE-S3 bucket outside this component
  #checkov:skip=CKV_AWS_144:Cross-region replication is out of scope for this component (trimmed from Cloud Posse's)
  #checkov:skip=CKV2_AWS_62:Event notifications are out of scope for this component (trimmed from Cloud Posse's)
  count = local.enabled ? 1 : 0

  bucket        = local.bucket_name
  force_destroy = var.force_destroy

  tags = { Name = local.bucket_name }

  lifecycle {
    precondition {
      condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", local.bucket_name))
      error_message = "The bucket name (currently \"${local.bucket_name}\") must be a valid S3 bucket name: 3-63 lowercase letters, digits, dots or hyphens. Shorten name or Environment, or set bucket_name."
    }
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  count = local.enabled ? 1 : 0

  bucket = aws_s3_bucket.this[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "this" {
  count = local.enabled ? 1 : 0

  bucket = aws_s3_bucket.this[0].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  count = local.enabled ? 1 : 0

  bucket = aws_s3_bucket.this[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = var.bucket_key_enabled
  }
}

resource "aws_s3_bucket_versioning" "this" {
  count = local.enabled ? 1 : 0

  bucket = aws_s3_bucket.this[0].id

  versioning_configuration {
    status = var.versioning_enabled ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_logging" "this" {
  count = local.enabled && var.logging != null ? 1 : 0

  bucket        = aws_s3_bucket.this[0].id
  target_bucket = var.logging.bucket_name
  target_prefix = var.logging.prefix
}

# Cloud Posse's allow_ssl_requests_only statement, always on, merged with the
# caller's source_policy_documents.
data "aws_iam_policy_document" "bucket" {
  count = local.enabled ? 1 : 0

  source_policy_documents = var.source_policy_documents

  statement {
    sid       = "ForceSSLOnlyAccess"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [local.bucket_arn, "${local.bucket_arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  count = local.enabled ? 1 : 0

  bucket = aws_s3_bucket.this[0].id
  policy = data.aws_iam_policy_document.bucket[0].json

  # A policy granting access could otherwise land before the public access
  # block that restricts it.
  depends_on = [aws_s3_bucket_public_access_block.this]
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  count = local.enabled && length(local.lifecycle_rules) > 0 ? 1 : 0

  bucket = aws_s3_bucket.this[0].id

  dynamic "rule" {
    for_each = local.lifecycle_rules

    content {
      id     = rule.value.id
      status = rule.value.enabled ? "Enabled" : "Disabled"

      dynamic "filter" {
        for_each = rule.value.filter_and == null ? ["empty"] : []
        content {}
      }

      dynamic "filter" {
        for_each = rule.value.filter_prefix_only == null ? [] : ["prefix"]
        content {
          prefix = rule.value.filter_prefix_only
        }
      }

      dynamic "filter" {
        for_each = rule.value.filter_and != null && rule.value.filter_prefix_only == null ? ["and"] : []
        content {
          and {
            object_size_greater_than = rule.value.filter_and.object_size_greater_than
            object_size_less_than    = rule.value.filter_and.object_size_less_than
            prefix                   = rule.value.filter_and.prefix
            # The provider rejects an empty map here.
            tags = length(rule.value.filter_and.tags) > 0 ? rule.value.filter_and.tags : null
          }
        }
      }

      dynamic "abort_incomplete_multipart_upload" {
        for_each = rule.value.abort_incomplete_multipart_upload_days == null ? [] : [1]
        content {
          days_after_initiation = rule.value.abort_incomplete_multipart_upload_days
        }
      }

      dynamic "expiration" {
        for_each = rule.value.expiration == null ? [] : [rule.value.expiration]
        content {
          date                         = expiration.value.date
          days                         = expiration.value.days
          expired_object_delete_marker = expiration.value.expired_object_delete_marker
        }
      }

      dynamic "noncurrent_version_expiration" {
        for_each = rule.value.noncurrent_version_expiration == null ? [] : [rule.value.noncurrent_version_expiration]
        iterator = expiration
        content {
          newer_noncurrent_versions = expiration.value.newer_noncurrent_versions
          noncurrent_days           = expiration.value.noncurrent_days
        }
      }

      dynamic "transition" {
        for_each = rule.value.transition
        content {
          date          = transition.value.date
          days          = transition.value.days
          storage_class = transition.value.storage_class
        }
      }

      dynamic "noncurrent_version_transition" {
        for_each = rule.value.noncurrent_version_transition
        iterator = transition
        content {
          newer_noncurrent_versions = transition.value.newer_noncurrent_versions
          noncurrent_days           = transition.value.noncurrent_days
          storage_class             = transition.value.storage_class
        }
      }
    }
  }

  # Versioning must be configured before lifecycle rules that act on
  # noncurrent versions.
  depends_on = [aws_s3_bucket_versioning.this]
}
