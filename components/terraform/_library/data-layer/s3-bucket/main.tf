locals {
  name_prefix = "${var.name_prefix}-${var.environment}"

  common_tags = merge(
    {
      Name        = var.bucket_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Module      = "s3-bucket"
    },
    var.tags
  )
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

#------------------------------------------------------------------------------
# S3 Bucket
#------------------------------------------------------------------------------
resource "aws_s3_bucket" "this" {
  bucket        = var.bucket_name
  force_destroy = var.force_destroy

  object_lock_enabled = var.enable_object_lock

  tags = local.common_tags
}

#------------------------------------------------------------------------------
# Versioning
#------------------------------------------------------------------------------
resource "aws_s3_bucket_versioning" "this" {
  count = var.enable_versioning ? 1 : 0

  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status     = "Enabled"
    mfa_delete = var.enable_mfa_delete ? "Enabled" : "Disabled"
  }
}

#------------------------------------------------------------------------------
# Server-Side Encryption
#------------------------------------------------------------------------------
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  count = var.enable_encryption ? 1 : 0

  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.encryption_type == "sse-s3" ? "AES256" : "aws:kms"
      kms_master_key_id = var.encryption_type != "sse-s3" ? var.kms_key_id : null
    }
    bucket_key_enabled = var.encryption_type != "sse-s3" ? true : false
  }
}

#------------------------------------------------------------------------------
# Public Access Block
#------------------------------------------------------------------------------
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = var.block_public_access
  block_public_policy     = var.block_public_access
  ignore_public_acls      = var.block_public_access
  restrict_public_buckets = var.block_public_access
}

#------------------------------------------------------------------------------
# Bucket Policy
#------------------------------------------------------------------------------
data "aws_iam_policy_document" "public_read" {
  count = var.enable_public_read && !var.block_public_access ? 1 : 0

  statement {
    sid    = "PublicReadGetObject"
    effect = "Allow"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = [
      "s3:GetObject"
    ]

    resources = [
      "${aws_s3_bucket.this.arn}/*"
    ]
  }
}

resource "aws_s3_bucket_policy" "this" {
  count = var.bucket_policy != null || (var.enable_public_read && !var.block_public_access) ? 1 : 0

  bucket = aws_s3_bucket.this.id
  policy = var.bucket_policy != null ? var.bucket_policy : data.aws_iam_policy_document.public_read[0].json

  depends_on = [aws_s3_bucket_public_access_block.this]
}

#------------------------------------------------------------------------------
# Lifecycle Configuration
#------------------------------------------------------------------------------
resource "aws_s3_bucket_lifecycle_configuration" "this" {
  count = length(var.lifecycle_rules) > 0 ? 1 : 0

  bucket = aws_s3_bucket.this.id

  dynamic "rule" {
    for_each = var.lifecycle_rules

    content {
      id     = rule.value.id
      status = rule.value.enabled ? "Enabled" : "Disabled"

      dynamic "filter" {
        for_each = rule.value.prefix != null || rule.value.tags != null ? [1] : []

        content {
          prefix = rule.value.prefix

          dynamic "tag" {
            for_each = rule.value.tags != null ? rule.value.tags : {}

            content {
              key   = tag.key
              value = tag.value
            }
          }
        }
      }

      dynamic "expiration" {
        for_each = rule.value.expiration != null ? [rule.value.expiration] : []

        content {
          days                         = expiration.value.days
          expired_object_delete_marker = expiration.value.expired_object_delete_marker
        }
      }

      dynamic "transition" {
        for_each = rule.value.transitions != null ? rule.value.transitions : []

        content {
          days          = transition.value.days
          storage_class = transition.value.storage_class
        }
      }

      dynamic "noncurrent_version_transition" {
        for_each = rule.value.noncurrent_version_transitions != null ? rule.value.noncurrent_version_transitions : []

        content {
          noncurrent_days = noncurrent_version_transition.value.noncurrent_days
          storage_class   = noncurrent_version_transition.value.storage_class
        }
      }

      dynamic "noncurrent_version_expiration" {
        for_each = rule.value.noncurrent_version_expiration != null ? [rule.value.noncurrent_version_expiration] : []

        content {
          noncurrent_days = noncurrent_version_expiration.value.noncurrent_days
        }
      }

      dynamic "abort_incomplete_multipart_upload" {
        for_each = rule.value.abort_incomplete_multipart_upload_days != null ? [1] : []

        content {
          days_after_initiation = rule.value.abort_incomplete_multipart_upload_days
        }
      }
    }
  }
}

#------------------------------------------------------------------------------
# Website Configuration
#------------------------------------------------------------------------------
resource "aws_s3_bucket_website_configuration" "this" {
  count = var.enable_website ? 1 : 0

  bucket = aws_s3_bucket.this.id

  index_document {
    suffix = var.website_index_document
  }

  error_document {
    key = var.website_error_document
  }
}

#------------------------------------------------------------------------------
# CORS Configuration
#------------------------------------------------------------------------------
resource "aws_s3_bucket_cors_configuration" "this" {
  count = length(var.cors_rules) > 0 ? 1 : 0

  bucket = aws_s3_bucket.this.id

  dynamic "cors_rule" {
    for_each = var.cors_rules

    content {
      allowed_headers = cors_rule.value.allowed_headers
      allowed_methods = cors_rule.value.allowed_methods
      allowed_origins = cors_rule.value.allowed_origins
      expose_headers  = cors_rule.value.expose_headers
      max_age_seconds = cors_rule.value.max_age_seconds
    }
  }
}

#------------------------------------------------------------------------------
# Logging
#------------------------------------------------------------------------------
resource "aws_s3_bucket_logging" "this" {
  count = var.enable_logging ? 1 : 0

  bucket = aws_s3_bucket.this.id

  target_bucket = var.logging_target_bucket
  target_prefix = var.logging_target_prefix
}

#------------------------------------------------------------------------------
# Replication
#------------------------------------------------------------------------------
resource "aws_s3_bucket_replication_configuration" "this" {
  count = var.enable_replication ? 1 : 0

  bucket = aws_s3_bucket.this.id
  role   = var.replication_role_arn

  dynamic "rule" {
    for_each = var.replication_rules

    content {
      id       = rule.value.id
      priority = rule.value.priority
      status   = "Enabled"

      dynamic "filter" {
        for_each = rule.value.prefix != null || rule.value.filter_tags != null ? [1] : []

        content {
          prefix = rule.value.prefix

          dynamic "tag" {
            for_each = rule.value.filter_tags != null ? rule.value.filter_tags : {}

            content {
              key   = tag.key
              value = tag.value
            }
          }
        }
      }

      destination {
        bucket        = rule.value.destination_bucket_arn
        storage_class = rule.value.destination_storage_class

        dynamic "encryption_configuration" {
          for_each = rule.value.replica_kms_key_id != null ? [1] : []

          content {
            replica_kms_key_id = rule.value.replica_kms_key_id
          }
        }
      }
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}

#------------------------------------------------------------------------------
# Object Lock Configuration
#------------------------------------------------------------------------------
resource "aws_s3_bucket_object_lock_configuration" "this" {
  count = var.enable_object_lock ? 1 : 0

  bucket = aws_s3_bucket.this.id

  rule {
    default_retention {
      mode = var.object_lock_mode
      days = var.object_lock_days
    }
  }
}

#------------------------------------------------------------------------------
# Intelligent-Tiering Configuration
#------------------------------------------------------------------------------
resource "aws_s3_bucket_intelligent_tiering_configuration" "this" {
  count = var.enable_intelligent_tiering ? 1 : 0

  bucket = aws_s3_bucket.this.id
  name   = "${var.bucket_name}-intelligent-tiering"

  tiering {
    access_tier = "ARCHIVE_ACCESS"
    days        = var.intelligent_tiering_archive_days
  }

  tiering {
    access_tier = "DEEP_ARCHIVE_ACCESS"
    days        = var.intelligent_tiering_deep_archive_days
  }
}

#------------------------------------------------------------------------------
# Event Notifications
#------------------------------------------------------------------------------
resource "aws_s3_bucket_notification" "this" {
  count = length(var.event_notifications) > 0 ? 1 : 0

  bucket = aws_s3_bucket.this.id

  dynamic "topic" {
    for_each = [for n in var.event_notifications : n if n.destination_type == "sns"]

    content {
      id            = topic.value.id
      topic_arn     = topic.value.destination_arn
      events        = topic.value.events
      filter_prefix = topic.value.filter_prefix
      filter_suffix = topic.value.filter_suffix
    }
  }

  dynamic "queue" {
    for_each = [for n in var.event_notifications : n if n.destination_type == "sqs"]

    content {
      id            = queue.value.id
      queue_arn     = queue.value.destination_arn
      events        = queue.value.events
      filter_prefix = queue.value.filter_prefix
      filter_suffix = queue.value.filter_suffix
    }
  }

  dynamic "lambda_function" {
    for_each = [for n in var.event_notifications : n if n.destination_type == "lambda"]

    content {
      id                  = lambda_function.value.id
      lambda_function_arn = lambda_function.value.destination_arn
      events              = lambda_function.value.events
      filter_prefix       = lambda_function.value.filter_prefix
      filter_suffix       = lambda_function.value.filter_suffix
    }
  }
}

#------------------------------------------------------------------------------
# Inventory Configuration
#------------------------------------------------------------------------------
resource "aws_s3_bucket_inventory" "this" {
  count = var.enable_inventory ? 1 : 0

  bucket = aws_s3_bucket.this.id
  name   = "${var.bucket_name}-inventory"

  included_object_versions = "All"

  schedule {
    frequency = "Daily"
  }

  destination {
    bucket {
      format     = "Parquet"
      bucket_arn = var.inventory_destination_bucket != null ? "arn:aws:s3:::${var.inventory_destination_bucket}" : aws_s3_bucket.this.arn
      prefix     = "inventory/"
    }
  }

  optional_fields = [
    "Size",
    "LastModifiedDate",
    "StorageClass",
    "ETag",
    "IsMultipartUploaded",
    "ReplicationStatus",
    "EncryptionStatus",
    "ObjectLockRetainUntilDate",
    "ObjectLockMode",
    "ObjectLockLegalHoldStatus",
    "IntelligentTieringAccessTier"
  ]
}

#------------------------------------------------------------------------------
# Request Metrics
#------------------------------------------------------------------------------
resource "aws_s3_bucket_metric" "this" {
  count = var.enable_request_metrics ? 1 : 0

  bucket = aws_s3_bucket.this.id
  name   = "${var.bucket_name}-metrics"
}
