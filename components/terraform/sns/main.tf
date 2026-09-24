# One SNS topic per instance with its subscriptions, modelled on Cloud Posse's
# aws-sns-topic component (which wraps cloudposse/sns-topic). Written as plain
# resources, like the other root components. The topic is encrypted with a
# customer managed KMS key, and always carries a topic policy: TLS-only, plus
# publish grants for the configured services (limited to this account by
# aws:SourceAccount) and IAM ARNs.

locals {
  enabled = var.enabled

  topic_name = "${var.tags["Environment"]}-${var.name}${var.fifo_topic ? ".fifo" : ""}"

  # Built from known values, not aws_sns_topic.this.arn, so the topic policy
  # is fully known at plan time (and so reviewable in the plan).
  account_id = data.aws_caller_identity.current.account_id
  topic_arn  = "arn:${data.aws_partition.current.partition}:sns:${var.region}:${local.account_id}:${local.topic_name}"
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

resource "aws_sns_topic" "this" {
  count = local.enabled ? 1 : 0

  name                        = local.topic_name
  display_name                = replace("${var.tags["Environment"]}-${var.name}", ".", "-")
  kms_master_key_id           = var.kms_key_arn
  delivery_policy             = var.delivery_policy
  fifo_topic                  = var.fifo_topic
  content_based_deduplication = var.fifo_topic ? var.content_based_deduplication : null

  tags = { Name = local.topic_name }
}

resource "aws_sns_topic_subscription" "this" {
  for_each = local.enabled ? var.subscribers : {}

  topic_arn              = aws_sns_topic.this[0].arn
  protocol               = each.value.protocol
  endpoint               = each.value.endpoint
  endpoint_auto_confirms = each.value.endpoint_auto_confirms
  raw_message_delivery   = each.value.raw_message_delivery
  filter_policy          = each.value.filter_policy
  filter_policy_scope    = each.value.filter_policy_scope
  subscription_role_arn  = each.value.subscription_role_arn
  redrive_policy = each.value.dead_letter_queue_arn != null ? jsonencode({
    deadLetterTargetArn = each.value.dead_letter_queue_arn
  }) : null
}

data "aws_iam_policy_document" "topic" {
  count = local.enabled ? 1 : 0

  policy_id = "SNSTopicsPub"

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["sns:Publish"]
    resources = [local.topic_arn]

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

  dynamic "statement" {
    for_each = length(var.allowed_aws_services_for_sns_published) > 0 ? [1] : []

    content {
      sid       = "AllowServicesToPublish"
      effect    = "Allow"
      actions   = ["sns:Publish"]
      resources = [local.topic_arn]

      principals {
        type        = "Service"
        identifiers = var.allowed_aws_services_for_sns_published
      }

      condition {
        test     = "StringEquals"
        variable = "aws:SourceAccount"
        values   = [local.account_id]
      }
    }
  }

  dynamic "statement" {
    for_each = length(var.allowed_iam_arns_for_sns_publish) > 0 ? [1] : []

    content {
      sid       = "AllowPrincipalsToPublish"
      effect    = "Allow"
      actions   = ["sns:Publish"]
      resources = [local.topic_arn]

      principals {
        type        = "AWS"
        identifiers = var.allowed_iam_arns_for_sns_publish
      }
    }
  }
}

resource "aws_sns_topic_policy" "this" {
  count = local.enabled ? 1 : 0

  arn    = aws_sns_topic.this[0].arn
  policy = var.sns_topic_policy_json != "" ? var.sns_topic_policy_json : data.aws_iam_policy_document.topic[0].json
}
