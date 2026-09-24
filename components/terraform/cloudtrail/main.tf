# Account CloudTrail trail, modelled on Cloud Posse aws-cloudtrail (the trail,
# a CloudWatch Logs log group and the role CloudTrail writes to it with) plus
# aws-cloudtrail-bucket (the S3 bucket the trail delivers to). Cloud Posse
# splits the bucket into its own component so an organization can share one
# audit-account bucket; every stack here is its own account with its own trail,
# so the bucket lives with the trail.
#
# security-monitoring reads cloudtrail_logs_log_group_name and puts the CIS AWS
# Foundations metric filters and alarms on it.

locals {
  name       = "${var.tags["Environment"]}-${var.name}"
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  # ARNs are built from names rather than read from the resources: the bucket
  # policy must exist before the trail it is scoped to, and policy documents
  # that reference only data sources and locals are known at plan time.
  trail_arn      = "arn:${local.partition}:cloudtrail:${var.region}:${local.account_id}:trail/${local.name}"
  bucket_name    = "${local.name}-${local.account_id}"
  bucket_arn     = "arn:${local.partition}:s3:::${local.bucket_name}"
  log_group_name = "/aws/cloudtrail/${local.name}"
  log_group_arn  = "arn:${local.partition}:logs:${var.region}:${local.account_id}:log-group:${local.log_group_name}"
}

##############################################
# Log bucket
##############################################

resource "aws_s3_bucket" "this" {
  #checkov:skip=CKV_AWS_18:The trail's log bucket; server access logs would need a second log bucket per account, and every read of the trail is itself recorded by the trail (S3 data events are GuardDuty's S3 protection)
  #checkov:skip=CKV_AWS_144:Single-region stacks; a replica bucket in a second region is a DR decision the stacks have not taken
  #checkov:skip=CKV2_AWS_62:Nothing consumes object-created notifications; alerting runs on the CloudWatch Logs copy of the trail
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

# S3 Bucket Key on (the Cloud Posse default): fewer KMS calls. It needs
# kms:Decrypt for cloudtrail.amazonaws.com in the key policy, which kms
# allow_cloudtrail grants (AllowCloudTrailDecrypt).
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
    id     = "trail-logs"
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
    sid       = "AWSCloudTrailAclCheck"
    actions   = ["s3:GetBucketAcl"]
    resources = [local.bucket_arn]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
  }

  statement {
    sid       = "AWSCloudTrailWrite"
    actions   = ["s3:PutObject"]
    resources = ["${local.bucket_arn}/AWSLogs/${local.account_id}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.bucket.json

  depends_on = [aws_s3_bucket_public_access_block.this]
}

##############################################
# CloudWatch Logs delivery
##############################################

resource "aws_cloudwatch_log_group" "this" {
  name              = local.log_group_name
  retention_in_days = var.cloudwatch_logs_retention_in_days
  kms_key_id        = var.kms_key_arn

  tags = { Name = local.log_group_name }
}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
  }
}

resource "aws_iam_role" "cloudwatch_logs" {
  name               = "${local.name}-cloudwatch-logs"
  assume_role_policy = data.aws_iam_policy_document.assume.json

  tags = { Name = "${local.name}-cloudwatch-logs" }
}

data "aws_iam_policy_document" "cloudwatch_logs" {
  statement {
    sid       = "WriteTrailLogStreams"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${local.log_group_arn}:log-stream:*"]
  }
}

resource "aws_iam_role_policy" "cloudwatch_logs" {
  name   = "${local.name}-cloudwatch-logs"
  role   = aws_iam_role.cloudwatch_logs.id
  policy = data.aws_iam_policy_document.cloudwatch_logs.json
}

##############################################
# Trail
##############################################

resource "aws_cloudtrail" "this" {
  #checkov:skip=CKV_AWS_252:A per-log-file SNS notification is not an alert; alerting runs on the CloudWatch Logs copy through security-monitoring's CIS metric filters and alarms
  name                          = local.name
  s3_bucket_name                = aws_s3_bucket.this.bucket
  kms_key_id                    = var.kms_key_arn
  enable_logging                = var.enable_logging
  enable_log_file_validation    = var.enable_log_file_validation
  is_multi_region_trail         = var.is_multi_region_trail
  include_global_service_events = var.include_global_service_events

  # CloudTrail requires the ":*" suffix on the log group ARN.
  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.this.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudwatch_logs.arn

  tags = { Name = local.name }

  # CloudTrail checks bucket and log-group access when the trail is created.
  depends_on = [aws_s3_bucket_policy.this, aws_iam_role_policy.cloudwatch_logs]
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}
