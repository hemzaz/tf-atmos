/*
 * S3 state backend with S3-native state locking.
 *
 * Terraform >= 1.10 locks state with a "<key>.tflock" object next to the state
 * (backend "s3" { use_lockfile = true }), so no DynamoDB lock table is created.
 *
 * Buckets:
 *   - terraform_state:             state files (versioned, SSE-KMS, TLS-only)
 *   - terraform_state_logs:        auxiliary log bucket (SSE-KMS, TLS-only)
 *   - terraform_state_access_logs: S3 server access logs for the two buckets above
 *                                  (SSE-S3: log delivery does not support SSE-KMS targets)
 */

locals {
  account_id = var.account_id != "" ? var.account_id : data.aws_caller_identity.current.account_id

  # Buckets that share the SSE-KMS / ownership / public-access / TLS baseline
  kms_buckets = {
    state = aws_s3_bucket.terraform_state
    logs  = aws_s3_bucket.terraform_state_logs
  }

  all_buckets = merge(
    local.kms_buckets,
    var.enable_access_logging ? { access_logs = aws_s3_bucket.terraform_state_access_logs[0] } : {}
  )
}

resource "aws_s3_bucket" "terraform_state" {
  bucket = var.bucket_name

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket" "terraform_state_logs" {
  bucket = "${var.bucket_name}-logs"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket" "terraform_state_access_logs" {
  count = var.enable_access_logging ? 1 : 0

  bucket = "${var.bucket_name}-access-logs"

  lifecycle {
    prevent_destroy = true
  }
}

# KMS key for state encryption
resource "aws_kms_key" "terraform_state_key" {
  description             = "KMS key for Terraform state encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  # A key policy cannot reference its own ARN; "*" means "this key"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableAccountAdministration"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${local.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      }
    ]
  })
}

resource "aws_kms_alias" "terraform_state_key_alias" {
  name          = "alias/${var.tenant}-terraform-state-key"
  target_key_id = aws_kms_key.terraform_state_key.key_id
}

# Disable ACLs on every bucket; the bucket owner owns all objects
resource "aws_s3_bucket_ownership_controls" "this" {
  for_each = local.all_buckets

  bucket = each.value.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  for_each = local.all_buckets

  bucket = each.value.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "kms" {
  for_each = local.kms_buckets

  bucket = each.value.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.terraform_state_key.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state_access_logs" {
  count = var.enable_access_logging ? 1 : 0

  bucket = aws_s3_bucket.terraform_state_access_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# TLS-only access (TLS 1.2+) for every bucket, plus S3 log delivery into the access logs bucket
data "aws_iam_policy_document" "bucket" {
  for_each = local.all_buckets

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [each.value.arn, "${each.value.arn}/*"]

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

  statement {
    sid       = "DenyOutdatedTLS"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [each.value.arn, "${each.value.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "NumericLessThan"
      variable = "s3:TlsVersion"
      values   = ["1.2"]
    }
  }

  dynamic "statement" {
    for_each = each.key == "access_logs" ? [1] : []
    content {
      sid       = "AllowS3ServerAccessLogDelivery"
      effect    = "Allow"
      actions   = ["s3:PutObject"]
      resources = ["${each.value.arn}/*"]

      principals {
        type        = "Service"
        identifiers = ["logging.s3.amazonaws.com"]
      }

      condition {
        test     = "ArnLike"
        variable = "aws:SourceArn"
        values   = [for bucket in local.kms_buckets : bucket.arn]
      }

      condition {
        test     = "StringEquals"
        variable = "aws:SourceAccount"
        values   = [local.account_id]
      }
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  for_each = local.all_buckets

  bucket = each.value.id
  policy = data.aws_iam_policy_document.bucket[each.key].json

  # A policy that grants public access would be rejected before the block is in place
  depends_on = [aws_s3_bucket_public_access_block.this]
}

resource "aws_s3_bucket_logging" "this" {
  for_each = var.enable_access_logging ? local.kms_buckets : {}

  bucket = each.value.id

  target_bucket = aws_s3_bucket.terraform_state_access_logs[0].id
  target_prefix = "${each.key}-bucket-logs/"

  depends_on = [aws_s3_bucket_policy.this]
}

resource "aws_s3_bucket_lifecycle_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    id     = "state-retention"
    status = "Enabled"

    filter {}

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_transition {
      noncurrent_days = 90
      storage_class   = "GLACIER"
    }

    noncurrent_version_expiration {
      noncurrent_days = 365
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.terraform_state]
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  for_each = var.enable_access_logging ? {
    logs        = aws_s3_bucket.terraform_state_logs
    access_logs = aws_s3_bucket.terraform_state_access_logs[0]
    } : {
    logs = aws_s3_bucket.terraform_state_logs
  }

  bucket = each.value.id

  rule {
    id     = "${replace(each.key, "_", "-")}-retention"
    status = "Enabled"

    filter {}

    expiration {
      days = 90
    }
  }
}
