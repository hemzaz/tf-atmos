##############################################
# SNS Topic - Main Configuration
##############################################

locals {
  topic_name = var.fifo_topic ? "${var.name_prefix}-${var.topic_name}.fifo" : "${var.name_prefix}-${var.topic_name}"
  kms_key_id = var.enable_encryption ? (var.kms_key_id != null ? var.kms_key_id : aws_kms_key.topic[0].arn) : null

  tags = merge(
    var.tags,
    {
      Name      = local.topic_name
      ManagedBy = "Terraform"
    }
  )
}

##############################################
# KMS Key for Topic Encryption
##############################################

resource "aws_kms_key" "topic" {
  count = var.enable_encryption && var.kms_key_id == null ? 1 : 0

  description             = "KMS key for SNS topic ${local.topic_name}"
  deletion_window_in_days = var.kms_deletion_window_days
  enable_key_rotation     = true

  policy = data.aws_iam_policy_document.kms_key_policy[0].json

  tags = local.tags
}

data "aws_iam_policy_document" "kms_key_policy" {
  count = var.enable_encryption && var.kms_key_id == null ? 1 : 0

  statement {
    sid    = "Enable IAM User Permissions"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "Allow SNS to use the key"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }

    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "Allow CloudWatch to use the key"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }

    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey"
    ]

    resources = ["*"]
  }
}

data "aws_caller_identity" "current" {}

resource "aws_kms_alias" "topic" {
  count = var.enable_encryption && var.kms_key_id == null ? 1 : 0

  name          = "alias/${local.topic_name}"
  target_key_id = aws_kms_key.topic[0].key_id
}

##############################################
# SNS Topic
##############################################

resource "aws_sns_topic" "main" {
  name              = local.topic_name
  display_name      = var.display_name
  fifo_topic        = var.fifo_topic
  content_based_deduplication = var.fifo_topic ? var.content_based_deduplication : null

  # Encryption
  kms_master_key_id = local.kms_key_id

  # Delivery policy
  delivery_policy = var.delivery_policy

  # HTTP configuration
  http_success_feedback_role_arn    = var.enable_delivery_status ? aws_iam_role.sns_feedback[0].arn : null
  http_success_feedback_sample_rate = var.http_success_feedback_sample_rate
  http_failure_feedback_role_arn    = var.enable_delivery_status ? aws_iam_role.sns_feedback[0].arn : null

  # Lambda configuration
  lambda_success_feedback_role_arn    = var.enable_delivery_status ? aws_iam_role.sns_feedback[0].arn : null
  lambda_success_feedback_sample_rate = var.lambda_success_feedback_sample_rate
  lambda_failure_feedback_role_arn    = var.enable_delivery_status ? aws_iam_role.sns_feedback[0].arn : null

  # SQS configuration
  sqs_success_feedback_role_arn    = var.enable_delivery_status ? aws_iam_role.sns_feedback[0].arn : null
  sqs_success_feedback_sample_rate = var.sqs_success_feedback_sample_rate
  sqs_failure_feedback_role_arn    = var.enable_delivery_status ? aws_iam_role.sns_feedback[0].arn : null

  # Firehose configuration
  firehose_success_feedback_role_arn    = var.enable_delivery_status ? aws_iam_role.sns_feedback[0].arn : null
  firehose_success_feedback_sample_rate = var.firehose_success_feedback_sample_rate
  firehose_failure_feedback_role_arn    = var.enable_delivery_status ? aws_iam_role.sns_feedback[0].arn : null

  # Application configuration
  application_success_feedback_role_arn    = var.enable_delivery_status ? aws_iam_role.sns_feedback[0].arn : null
  application_success_feedback_sample_rate = var.application_success_feedback_sample_rate
  application_failure_feedback_role_arn    = var.enable_delivery_status ? aws_iam_role.sns_feedback[0].arn : null

  tags = local.tags
}

##############################################
# IAM Role for Delivery Status Logging
##############################################

resource "aws_iam_role" "sns_feedback" {
  count = var.enable_delivery_status ? 1 : 0

  name               = "${local.topic_name}-delivery-status"
  assume_role_policy = data.aws_iam_policy_document.sns_feedback_assume[0].json

  tags = local.tags
}

data "aws_iam_policy_document" "sns_feedback_assume" {
  count = var.enable_delivery_status ? 1 : 0

  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role_policy" "sns_feedback" {
  count = var.enable_delivery_status ? 1 : 0

  name   = "sns-delivery-status"
  role   = aws_iam_role.sns_feedback[0].id
  policy = data.aws_iam_policy_document.sns_feedback_policy[0].json
}

data "aws_iam_policy_document" "sns_feedback_policy" {
  count = var.enable_delivery_status ? 1 : 0

  statement {
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = ["*"]
  }
}

##############################################
# Topic Policy
##############################################

resource "aws_sns_topic_policy" "main" {
  count = var.topic_policy != null || length(var.allowed_publishers) > 0 ? 1 : 0

  arn    = aws_sns_topic.main.arn
  policy = var.topic_policy != null ? var.topic_policy : data.aws_iam_policy_document.topic[0].json
}

data "aws_iam_policy_document" "topic" {
  count = var.topic_policy == null && length(var.allowed_publishers) > 0 ? 1 : 0

  statement {
    sid    = "AllowPublish"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = var.allowed_publishers
    }

    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.main.arn]
  }

  dynamic "statement" {
    for_each = var.allow_cloudwatch_events ? [1] : []
    content {
      sid    = "AllowCloudWatchEvents"
      effect = "Allow"

      principals {
        type        = "Service"
        identifiers = ["events.amazonaws.com"]
      }

      actions   = ["sns:Publish"]
      resources = [aws_sns_topic.main.arn]
    }
  }
}

##############################################
# Subscriptions
##############################################

resource "aws_sns_topic_subscription" "sqs" {
  for_each = { for idx, sub in var.sqs_subscriptions : idx => sub }

  topic_arn            = aws_sns_topic.main.arn
  protocol             = "sqs"
  endpoint             = each.value.queue_arn
  raw_message_delivery = lookup(each.value, "raw_message_delivery", false)
  filter_policy        = lookup(each.value, "filter_policy", null)
  filter_policy_scope  = lookup(each.value, "filter_policy_scope", "MessageAttributes")
  redrive_policy       = lookup(each.value, "redrive_policy", null)
}

resource "aws_sns_topic_subscription" "lambda" {
  for_each = { for idx, sub in var.lambda_subscriptions : idx => sub }

  topic_arn     = aws_sns_topic.main.arn
  protocol      = "lambda"
  endpoint      = each.value.function_arn
  filter_policy = lookup(each.value, "filter_policy", null)
  filter_policy_scope = lookup(each.value, "filter_policy_scope", "MessageAttributes")
  redrive_policy = lookup(each.value, "redrive_policy", null)
}

resource "aws_sns_topic_subscription" "http" {
  for_each = { for idx, sub in var.http_subscriptions : idx => sub }

  topic_arn            = aws_sns_topic.main.arn
  protocol             = lookup(each.value, "use_https", true) ? "https" : "http"
  endpoint             = each.value.endpoint_url
  raw_message_delivery = lookup(each.value, "raw_message_delivery", false)
  filter_policy        = lookup(each.value, "filter_policy", null)
  filter_policy_scope  = lookup(each.value, "filter_policy_scope", "MessageAttributes")
  redrive_policy       = lookup(each.value, "redrive_policy", null)
}

resource "aws_sns_topic_subscription" "email" {
  for_each = { for idx, email in var.email_subscriptions : idx => email }

  topic_arn = aws_sns_topic.main.arn
  protocol  = "email"
  endpoint  = each.value
}

##############################################
# CloudWatch Metrics
##############################################

resource "aws_cloudwatch_metric_alarm" "message_publish_failed" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.topic_name}-publish-failed"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "NumberOfNotificationsFailed"
  namespace           = "AWS/SNS"
  period              = var.alarm_period_seconds
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "SNS message publish failures for ${local.topic_name}"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.alarm_ok_actions

  dimensions = {
    TopicName = aws_sns_topic.main.name
  }

  tags = local.tags
}
