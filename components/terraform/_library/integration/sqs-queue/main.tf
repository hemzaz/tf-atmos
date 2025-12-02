##############################################
# SQS Queue - Main Configuration
##############################################

locals {
  queue_name     = var.fifo_queue ? "${var.name_prefix}-${var.queue_name}.fifo" : "${var.name_prefix}-${var.queue_name}"
  dlq_name       = var.enable_dead_letter_queue ? (var.fifo_queue ? "${var.name_prefix}-${var.queue_name}-dlq.fifo" : "${var.name_prefix}-${var.queue_name}-dlq") : null
  kms_key_id     = var.enable_encryption ? (var.kms_key_id != null ? var.kms_key_id : aws_kms_key.queue[0].arn) : null
  redrive_policy = var.enable_dead_letter_queue ? jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq[0].arn
    maxReceiveCount     = var.max_receive_count
  }) : null

  tags = merge(
    var.tags,
    {
      Name      = local.queue_name
      ManagedBy = "Terraform"
    }
  )
}

##############################################
# KMS Key for Queue Encryption
##############################################

resource "aws_kms_key" "queue" {
  count = var.enable_encryption && var.kms_key_id == null ? 1 : 0

  description             = "KMS key for SQS queue ${local.queue_name}"
  deletion_window_in_days = var.kms_deletion_window_days
  enable_key_rotation     = true

  tags = local.tags
}

resource "aws_kms_alias" "queue" {
  count = var.enable_encryption && var.kms_key_id == null ? 1 : 0

  name          = "alias/${local.queue_name}"
  target_key_id = aws_kms_key.queue[0].key_id
}

##############################################
# Dead Letter Queue
##############################################

resource "aws_sqs_queue" "dlq" {
  count = var.enable_dead_letter_queue ? 1 : 0

  name                       = local.dlq_name
  fifo_queue                 = var.fifo_queue
  content_based_deduplication = var.fifo_queue ? var.content_based_deduplication : null
  message_retention_seconds  = var.dlq_message_retention_seconds
  kms_master_key_id          = local.kms_key_id
  kms_data_key_reuse_period_seconds = var.enable_encryption ? var.kms_data_key_reuse_seconds : null

  tags = merge(
    local.tags,
    {
      Name = local.dlq_name
      Type = "DeadLetterQueue"
    }
  )
}

##############################################
# Main SQS Queue
##############################################

resource "aws_sqs_queue" "main" {
  name                       = local.queue_name
  fifo_queue                 = var.fifo_queue
  content_based_deduplication = var.fifo_queue ? var.content_based_deduplication : null

  # Message configuration
  message_retention_seconds  = var.message_retention_seconds
  visibility_timeout_seconds = var.visibility_timeout_seconds
  delay_seconds              = var.delay_seconds
  receive_wait_time_seconds  = var.receive_wait_time_seconds
  max_message_size           = var.max_message_size

  # Encryption
  kms_master_key_id                = local.kms_key_id
  kms_data_key_reuse_period_seconds = var.enable_encryption ? var.kms_data_key_reuse_seconds : null
  sqs_managed_sse_enabled           = !var.enable_encryption

  # Dead letter queue
  redrive_policy = local.redrive_policy

  # Redrive allow policy for DLQ
  redrive_allow_policy = var.enable_dead_letter_queue && var.enable_redrive_allow_policy ? jsonencode({
    redrivePermission = var.redrive_permission
    sourceQueueArns   = var.source_queue_arns
  }) : null

  tags = local.tags
}

##############################################
# Queue Policy for Cross-Account Access
##############################################

resource "aws_sqs_queue_policy" "main" {
  count = var.queue_policy != null || length(var.allowed_principals) > 0 ? 1 : 0

  queue_url = aws_sqs_queue.main.url

  policy = var.queue_policy != null ? var.queue_policy : data.aws_iam_policy_document.queue[0].json
}

data "aws_iam_policy_document" "queue" {
  count = var.queue_policy == null && length(var.allowed_principals) > 0 ? 1 : 0

  statement {
    sid    = "AllowSendMessage"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = var.allowed_principals
    }

    actions = [
      "sqs:SendMessage",
      "sqs:SendMessageBatch"
    ]

    resources = [aws_sqs_queue.main.arn]
  }

  dynamic "statement" {
    for_each = var.allow_sns_publish ? [1] : []
    content {
      sid    = "AllowSNSPublish"
      effect = "Allow"

      principals {
        type        = "Service"
        identifiers = ["sns.amazonaws.com"]
      }

      actions   = ["sqs:SendMessage"]
      resources = [aws_sqs_queue.main.arn]

      condition {
        test     = "ArnEquals"
        variable = "aws:SourceArn"
        values   = var.sns_topic_arns
      }
    }
  }
}

##############################################
# CloudWatch Alarms
##############################################

resource "aws_cloudwatch_metric_alarm" "queue_depth" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.queue_name}-queue-depth"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = var.alarm_period_seconds
  statistic           = "Average"
  threshold           = var.alarm_queue_depth_threshold
  alarm_description   = "Queue depth exceeds threshold for ${local.queue_name}"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.alarm_ok_actions

  dimensions = {
    QueueName = aws_sqs_queue.main.name
  }

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "age_of_oldest_message" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.queue_name}-message-age"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "ApproximateAgeOfOldestMessage"
  namespace           = "AWS/SQS"
  period              = var.alarm_period_seconds
  statistic           = "Maximum"
  threshold           = var.alarm_message_age_threshold
  alarm_description   = "Oldest message age exceeds threshold for ${local.queue_name}"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.alarm_ok_actions

  dimensions = {
    QueueName = aws_sqs_queue.main.name
  }

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "dlq_messages" {
  count = var.enable_cloudwatch_alarms && var.enable_dead_letter_queue ? 1 : 0

  alarm_name          = "${local.queue_name}-dlq-messages"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Average"
  threshold           = 0
  alarm_description   = "Messages detected in DLQ for ${local.queue_name}"
  alarm_actions       = var.alarm_actions

  dimensions = {
    QueueName = aws_sqs_queue.dlq[0].name
  }

  tags = local.tags
}
