# One Kinesis Data Firehose delivery stream per instance, delivering to S3
# (extended_s3), modelled on Cloud Posse's aws-kinesis-firehose-stream
# (https://github.com/cloudposse-terraform-components/aws-kinesis-firehose-stream).
# Deviations from upstream, which reads its bucket and log groups through
# remote state and creates one role with S3 access:
#   - The bucket, source and keys are inputs (wired with !terraform.state in
#     the stacks), not remote-state modules.
#   - Source: direct put (upstream's only mode) or a Kinesis stream, read
#     through a separate source role that can only read that stream.
#   - Encryption: a customer managed key for S3 objects and the log group
#     (upstream's encryption_enabled uses the AWS managed aws/s3 key), and
#     server-side encryption of a direct put stream (CMK when given, else an
#     AWS owned key).
#   - Delivery errors are logged to a log group this component creates
#     (upstream disables delivery logging). Upstream's CloudWatch Logs
#     subscription filters (log groups as producers) are not carried over.
#   - Names follow this repo (<Environment>-<name>), not the null-label id.
# Data format conversion (Glue schema, Parquet) and dynamic partitioning are
# not implemented yet (see README).

locals {
  enabled = var.enabled
  name    = "${var.tags["Environment"]}-${var.name}"

  kinesis_source = local.enabled && var.kinesis_source_stream_arn != null

  delivery_role_name = "${local.name}-delivery"
  source_role_name   = "${local.name}-source"
  log_group_name     = "/aws/kinesisfirehose/${local.name}"
  log_stream_name    = "DestinationDelivery"

  # Firehose assumes both roles; aws:SourceAccount keeps another account's
  # delivery stream from using them (confused deputy).
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "firehose.amazonaws.com" }
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
      }
    }]
  })
}

data "aws_caller_identity" "current" {}

resource "aws_cloudwatch_log_group" "this" {
  # checkov:skip=CKV_AWS_338:Retention mirrors the repo's other log groups (log_retention_days, default 90) and is a per-stack cost decision, not a module one.
  count = local.enabled ? 1 : 0

  name              = local.log_group_name
  kms_key_id        = var.kms_key_arn
  retention_in_days = var.log_retention_days

  tags = { Name = local.log_group_name }
}

# Firehose writes to an existing stream; it does not create one.
resource "aws_cloudwatch_log_stream" "delivery" {
  count = local.enabled ? 1 : 0

  name           = local.log_stream_name
  log_group_name = aws_cloudwatch_log_group.this[0].name
}

# Delivery role: write to the destination bucket, encrypt with the key
# through S3 only, and log delivery errors to this stream's log stream.
resource "aws_iam_role" "delivery" {
  count = local.enabled ? 1 : 0

  name               = local.delivery_role_name
  assume_role_policy = local.assume_role_policy

  tags = { Name = local.delivery_role_name }

  lifecycle {
    precondition {
      condition     = length(local.name) <= 64 && length(local.delivery_role_name) <= 64
      error_message = "The delivery stream name (<Environment>-<name>, \"${local.name}\") and its role name (\"${local.delivery_role_name}\") must be 64 characters or fewer."
    }
  }
}

resource "aws_iam_role_policy" "delivery" {
  count = local.enabled ? 1 : 0

  name = "delivery"
  role = aws_iam_role.delivery[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "S3Bucket"
        Effect   = "Allow"
        Action   = ["s3:GetBucketLocation", "s3:ListBucket", "s3:ListBucketMultipartUploads"]
        Resource = var.s3_bucket_arn
      },
      {
        Sid      = "S3Objects"
        Effect   = "Allow"
        Action   = ["s3:AbortMultipartUpload", "s3:GetObject", "s3:PutObject"]
        Resource = "${var.s3_bucket_arn}/*"
      },
      {
        # The encryption context is the object ARN, or the bucket ARN when
        # the bucket uses an S3 Bucket Key (the s3 component's default).
        Sid      = "KMSThroughS3"
        Effect   = "Allow"
        Action   = ["kms:GenerateDataKey", "kms:Decrypt"]
        Resource = var.kms_key_arn
        Condition = {
          StringEquals = {
            "kms:ViaService" = "s3.${var.region}.amazonaws.com"
          }
          StringLike = {
            "kms:EncryptionContext:aws:s3:arn" = [var.s3_bucket_arn, "${var.s3_bucket_arn}/*"]
          }
        }
      },
      {
        Sid      = "DeliveryLogs"
        Effect   = "Allow"
        Action   = ["logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.this[0].arn}:log-stream:${local.log_stream_name}"
      },
    ]
  })
}

# Source role (Kinesis source only): read the one source stream, and decrypt
# it through Kinesis only.
resource "aws_iam_role" "source" {
  count = local.kinesis_source ? 1 : 0

  name               = local.source_role_name
  assume_role_policy = local.assume_role_policy

  tags = { Name = local.source_role_name }
}

resource "aws_iam_role_policy" "source" {
  count = local.kinesis_source ? 1 : 0

  name = "source"
  role = aws_iam_role.source[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [{
        Sid      = "KinesisRead"
        Effect   = "Allow"
        Action   = ["kinesis:DescribeStream", "kinesis:GetRecords", "kinesis:GetShardIterator", "kinesis:ListShards"]
        Resource = var.kinesis_source_stream_arn
      }],
      var.kinesis_source_kms_key_arn == null ? [] : [{
        Sid      = "KMSThroughKinesis"
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = var.kinesis_source_kms_key_arn
        Condition = {
          StringEquals = {
            "kms:ViaService"                        = "kinesis.${var.region}.amazonaws.com"
            "kms:EncryptionContext:aws:kinesis:arn" = var.kinesis_source_stream_arn
          }
        }
      }]
    )
  })
}

resource "aws_kinesis_firehose_delivery_stream" "this" {
  # checkov:skip=CKV_AWS_241:A direct put stream uses server_side_encryption_kms_key_arn when set; a Kinesis source cannot take stream SSE (its data stays encrypted by the source stream's key).
  count = local.enabled ? 1 : 0

  name        = local.name
  destination = "extended_s3"

  dynamic "kinesis_source_configuration" {
    for_each = local.kinesis_source ? [1] : []
    content {
      kinesis_stream_arn = var.kinesis_source_stream_arn
      role_arn           = aws_iam_role.source[0].arn
    }
  }

  # Direct put streams are always encrypted: with the given CMK, or an AWS
  # owned key. Firehose rejects this block for a Kinesis source.
  dynamic "server_side_encryption" {
    for_each = local.kinesis_source ? [] : [1]
    content {
      enabled  = true
      key_type = var.server_side_encryption_kms_key_arn == null ? "AWS_OWNED_CMK" : "CUSTOMER_MANAGED_CMK"
      key_arn  = var.server_side_encryption_kms_key_arn
    }
  }

  extended_s3_configuration {
    role_arn            = aws_iam_role.delivery[0].arn
    bucket_arn          = var.s3_bucket_arn
    prefix              = var.s3_prefix
    error_output_prefix = var.s3_error_output_prefix
    buffering_size      = var.buffering_size
    buffering_interval  = var.buffering_interval
    compression_format  = var.compression_format
    kms_key_arn         = var.kms_key_arn

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.this[0].name
      log_stream_name = aws_cloudwatch_log_stream.delivery[0].name
    }
  }

  tags = { Name = local.name }

  # Firehose validates the roles when the stream is created; IAM is
  # eventually consistent, so the policies must exist first.
  depends_on = [aws_iam_role_policy.delivery, aws_iam_role_policy.source]
}
