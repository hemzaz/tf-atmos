locals {
  name_prefix = "${var.name_prefix}-${var.environment}"

  common_tags = merge(
    {
      Name        = "${local.name_prefix}-s3-replication"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Module      = "s3-replication"
    },
    var.tags
  )
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

#------------------------------------------------------------------------------
# Source Bucket Configuration
#------------------------------------------------------------------------------
resource "aws_s3_bucket_versioning" "source" {
  bucket = var.source_bucket_id

  versioning_configuration {
    status = "Enabled"
  }
}

#------------------------------------------------------------------------------
# Destination Bucket Configuration
#------------------------------------------------------------------------------
resource "aws_s3_bucket_versioning" "destination" {
  provider = aws.replica

  bucket = var.destination_bucket_id

  versioning_configuration {
    status = "Enabled"
  }
}

#------------------------------------------------------------------------------
# IAM Role for Replication
#------------------------------------------------------------------------------
resource "aws_iam_role" "replication" {
  name               = "${local.name_prefix}-s3-replication-role"
  assume_role_policy = data.aws_iam_policy_document.replication_assume_role.json

  tags = local.common_tags
}

data "aws_iam_policy_document" "replication_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_policy" "replication" {
  name        = "${local.name_prefix}-s3-replication-policy"
  description = "Policy for S3 replication"
  policy      = data.aws_iam_policy_document.replication.json

  tags = local.common_tags
}

data "aws_iam_policy_document" "replication" {
  statement {
    sid    = "SourceBucketPermissions"
    effect = "Allow"

    actions = [
      "s3:GetReplicationConfiguration",
      "s3:ListBucket"
    ]

    resources = [
      "arn:${data.aws_partition.current.partition}:s3:::${var.source_bucket_id}"
    ]
  }

  statement {
    sid    = "SourceObjectPermissions"
    effect = "Allow"

    actions = [
      "s3:GetObjectVersionForReplication",
      "s3:GetObjectVersionAcl",
      "s3:GetObjectVersionTagging"
    ]

    resources = [
      "arn:${data.aws_partition.current.partition}:s3:::${var.source_bucket_id}/*"
    ]
  }

  statement {
    sid    = "DestinationBucketPermissions"
    effect = "Allow"

    actions = [
      "s3:ReplicateObject",
      "s3:ReplicateDelete",
      "s3:ReplicateTags"
    ]

    resources = [
      "arn:${data.aws_partition.current.partition}:s3:::${var.destination_bucket_id}/*"
    ]
  }

  dynamic "statement" {
    for_each = var.enable_kms_encryption ? [1] : []

    content {
      sid    = "SourceKMSPermissions"
      effect = "Allow"

      actions = [
        "kms:Decrypt"
      ]

      resources = [var.source_kms_key_arn]

      condition {
        test     = "StringLike"
        variable = "kms:ViaService"
        values   = ["s3.${data.aws_region.current.name}.amazonaws.com"]
      }

      condition {
        test     = "StringLike"
        variable = "kms:EncryptionContext:aws:s3:arn"
        values   = ["arn:${data.aws_partition.current.partition}:s3:::${var.source_bucket_id}/*"]
      }
    }
  }

  dynamic "statement" {
    for_each = var.enable_kms_encryption ? [1] : []

    content {
      sid    = "DestinationKMSPermissions"
      effect = "Allow"

      actions = [
        "kms:Encrypt"
      ]

      resources = [var.destination_kms_key_arn]

      condition {
        test     = "StringLike"
        variable = "kms:ViaService"
        values   = ["s3.${var.destination_region}.amazonaws.com"]
      }

      condition {
        test     = "StringLike"
        variable = "kms:EncryptionContext:aws:s3:arn"
        values   = ["arn:${data.aws_partition.current.partition}:s3:::${var.destination_bucket_id}/*"]
      }
    }
  }
}

resource "aws_iam_role_policy_attachment" "replication" {
  role       = aws_iam_role.replication.name
  policy_arn = aws_iam_policy.replication.arn
}

#------------------------------------------------------------------------------
# S3 Bucket Replication Configuration
#------------------------------------------------------------------------------
resource "aws_s3_bucket_replication_configuration" "this" {
  depends_on = [
    aws_s3_bucket_versioning.source,
    aws_s3_bucket_versioning.destination
  ]

  role   = aws_iam_role.replication.arn
  bucket = var.source_bucket_id

  dynamic "rule" {
    for_each = var.replication_rules

    content {
      id       = rule.value.id
      priority = rule.value.priority
      status   = "Enabled"

      dynamic "filter" {
        for_each = lookup(rule.value, "filter_prefix", null) != null || lookup(rule.value, "filter_tags", null) != null ? [1] : []

        content {
          prefix = lookup(rule.value, "filter_prefix", null)

          dynamic "tag" {
            for_each = lookup(rule.value, "filter_tags", {})

            content {
              key   = tag.key
              value = tag.value
            }
          }
        }
      }

      delete_marker_replication {
        status = lookup(rule.value, "delete_marker_replication_status", "Disabled")
      }

      destination {
        bucket        = "arn:${data.aws_partition.current.partition}:s3:::${var.destination_bucket_id}"
        storage_class = lookup(rule.value, "destination_storage_class", "STANDARD")

        dynamic "encryption_configuration" {
          for_each = var.enable_kms_encryption ? [1] : []

          content {
            replica_kms_key_id = var.destination_kms_key_arn
          }
        }

        dynamic "replication_time" {
          for_each = lookup(rule.value, "enable_replication_time_control", false) ? [1] : []

          content {
            status = "Enabled"
            time {
              minutes = lookup(rule.value, "replication_time_minutes", 15)
            }
          }
        }

        dynamic "metrics" {
          for_each = lookup(rule.value, "enable_metrics", false) ? [1] : []

          content {
            status = "Enabled"
            event_threshold {
              minutes = lookup(rule.value, "metrics_event_threshold_minutes", 15)
            }
          }
        }

        dynamic "access_control_translation" {
          for_each = var.destination_account_id != null ? [1] : []

          content {
            owner = "Destination"
          }
        }

        account = var.destination_account_id
      }

      dynamic "source_selection_criteria" {
        for_each = lookup(rule.value, "enable_replica_modifications", false) || var.enable_kms_encryption ? [1] : []

        content {
          dynamic "replica_modifications" {
            for_each = lookup(rule.value, "enable_replica_modifications", false) ? [1] : []

            content {
              status = "Enabled"
            }
          }

          dynamic "sse_kms_encrypted_objects" {
            for_each = var.enable_kms_encryption ? [1] : []

            content {
              status = "Enabled"
            }
          }
        }
      }
    }
  }
}

#------------------------------------------------------------------------------
# S3 Batch Replication Job (for existing objects)
#------------------------------------------------------------------------------
resource "aws_s3_bucket_object_lock_configuration" "source" {
  count = var.enable_object_lock ? 1 : 0

  bucket = var.source_bucket_id

  rule {
    default_retention {
      mode = var.object_lock_mode
      days = var.object_lock_days
    }
  }
}

#------------------------------------------------------------------------------
# CloudWatch Alarms
#------------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "replication_latency" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.name_prefix}-s3-replication-latency-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ReplicationLatency"
  namespace           = "AWS/S3"
  period              = 300
  statistic           = "Average"
  threshold           = var.replication_latency_threshold_seconds
  alarm_description   = "S3 replication latency is high"
  treat_missing_data  = "notBreaching"

  dimensions = {
    SourceBucket      = var.source_bucket_id
    DestinationBucket = var.destination_bucket_id
    RuleId            = var.replication_rules[0].id
  }

  alarm_actions = var.alarm_actions

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "bytes_pending_replication" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.name_prefix}-s3-bytes-pending-replication-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "BytesPendingReplication"
  namespace           = "AWS/S3"
  period              = 300
  statistic           = "Average"
  threshold           = var.bytes_pending_replication_threshold
  alarm_description   = "S3 bytes pending replication is high"
  treat_missing_data  = "notBreaching"

  dimensions = {
    SourceBucket      = var.source_bucket_id
    DestinationBucket = var.destination_bucket_id
    RuleId            = var.replication_rules[0].id
  }

  alarm_actions = var.alarm_actions

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "operations_failed_replication" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.name_prefix}-s3-operations-failed-replication"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "OperationsFailedReplication"
  namespace           = "AWS/S3"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "S3 replication operations failed"
  treat_missing_data  = "notBreaching"

  dimensions = {
    SourceBucket      = var.source_bucket_id
    DestinationBucket = var.destination_bucket_id
    RuleId            = var.replication_rules[0].id
  }

  alarm_actions = var.alarm_actions

  tags = local.common_tags
}
