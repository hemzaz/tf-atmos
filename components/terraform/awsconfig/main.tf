# AWS Config recorder for one account/region, modelled on Cloud Posse aws-config
# (recorder, delivery channel, and an IAM role with the AWS managed
# AWS_ConfigRole policy) plus aws-config-bucket (the S3 bucket snapshots are
# delivered to). Cloud Posse keeps the bucket in its own component so an
# organization can share one audit-account bucket; each stack here is its own
# account, so the bucket lives with the recorder. The name has no hyphen
# (awsconfig, not aws-config) per the repo's component naming rule.
#
# Security Hub's FSBP and CIS controls are evaluated by AWS Config rules, so
# without a recorder most of them report "no data".

locals {
  name       = "${var.tags["Environment"]}-${var.name}"
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  # Built from names so the policy documents are known at plan time.
  bucket_name = "${local.name}-${local.account_id}"
  bucket_arn  = "arn:${local.partition}:s3:::${local.bucket_name}"
  # AWS Config writes under this prefix (no key prefix is configured).
  delivery_prefix_arn = "${local.bucket_arn}/AWSLogs/${local.account_id}/Config/*"
}

##############################################
# Storage bucket
##############################################

resource "aws_s3_bucket" "this" {
  #checkov:skip=CKV_AWS_18:Configuration snapshots and history; server access logs would need a second log bucket per account, and management access to the bucket is recorded by CloudTrail
  #checkov:skip=CKV_AWS_144:Single-region stacks; a replica bucket in a second region is a DR decision the stacks have not taken
  #checkov:skip=CKV2_AWS_62:Nothing consumes object-created notifications; Config changes reach Security Hub through Config rules, not through the bucket
  bucket        = local.bucket_name
  force_destroy = var.force_destroy

  tags = { Name = local.bucket_name }
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "config-history"
    status = "Enabled"

    filter {}

    transition {
      days          = var.bucket_glacier_transition_days
      storage_class = "GLACIER"
    }

    expiration {
      days = var.bucket_expiration_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  lifecycle {
    precondition {
      condition     = var.bucket_glacier_transition_days < var.bucket_expiration_days
      error_message = "bucket_glacier_transition_days must be less than bucket_expiration_days."
    }
  }
}

# TLS only, plus the AWS Config service-principal statements AWS documents for
# a delivery bucket, limited to this account by aws:SourceAccount.
data "aws_iam_policy_document" "bucket" {
  statement {
    sid       = "DenyInsecureTransport"
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

  statement {
    sid       = "AWSConfigBucketPermissionsCheck"
    actions   = ["s3:GetBucketAcl", "s3:ListBucket"]
    resources = [local.bucket_arn]

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }

  statement {
    sid       = "AWSConfigBucketDelivery"
    actions   = ["s3:PutObject"]
    resources = [local.delivery_prefix_arn]

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.bucket.json

  depends_on = [aws_s3_bucket_public_access_block.this]
}

##############################################
# IAM role
##############################################

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "${local.name}-recorder"
  assume_role_policy = data.aws_iam_policy_document.assume.json

  tags = { Name = "${local.name}-recorder" }
}

# Read access to every recorded resource type, maintained by AWS.
resource "aws_iam_role_policy_attachment" "config" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AWS_ConfigRole"
}

# Delivery to this component's bucket with its CMK. The managed policy grants
# no S3 or KMS write access.
data "aws_iam_policy_document" "delivery" {
  statement {
    sid       = "CheckBucket"
    actions   = ["s3:GetBucketAcl"]
    resources = [local.bucket_arn]
  }

  statement {
    sid       = "DeliverSnapshots"
    actions   = ["s3:PutObject"]
    resources = [local.delivery_prefix_arn]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }

  statement {
    sid       = "EncryptSnapshots"
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = [var.kms_key_arn]
  }
}

resource "aws_iam_role_policy" "delivery" {
  name   = "${local.name}-delivery"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.delivery.json
}

##############################################
# Recorder and delivery channel
##############################################

resource "aws_config_configuration_recorder" "this" {
  name     = local.name
  role_arn = aws_iam_role.this.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = var.include_global_resource_types
  }

  recording_mode {
    recording_frequency = var.recording_frequency
  }
}

resource "aws_config_delivery_channel" "this" {
  name           = local.name
  s3_bucket_name = aws_s3_bucket.this.bucket
  s3_kms_key_arn = var.kms_key_arn

  snapshot_delivery_properties {
    delivery_frequency = var.delivery_frequency
  }

  depends_on = [
    aws_config_configuration_recorder.this,
    aws_s3_bucket_policy.this,
    aws_iam_role_policy.delivery,
  ]
}

resource "aws_config_configuration_recorder_status" "this" {
  name       = aws_config_configuration_recorder.this.name
  is_enabled = var.enable_recorder

  depends_on = [aws_config_delivery_channel.this]
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}
