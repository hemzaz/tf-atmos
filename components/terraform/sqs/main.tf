# One SQS queue per instance, with an optional dead-letter queue, modelled on
# Cloud Posse's aws-sqs-queue component (which wraps
# terraform-aws-modules/sqs and cloudposse/iam-policy). Written as plain
# resources, like the other root components. Both queues are encrypted with a
# customer managed KMS key, never SQS-managed SSE.

locals {
  enabled = var.enabled

  fifo_suffix = var.fifo_queue ? ".fifo" : ""
  base_name   = "${var.tags["Environment"]}-${var.name}"
  queue_name  = "${local.base_name}${local.fifo_suffix}"
  dlq_name    = "${local.base_name}-${var.dlq_name_suffix}${local.fifo_suffix}"

  dlq_enabled    = local.enabled && var.dlq_enabled
  policy_enabled = local.enabled && length(var.iam_policy) > 0

  # Built from known values, not aws_sqs_queue.*.arn, so the queue policy is
  # fully known at plan time (and so reviewable in the plan).
  account_id = data.aws_caller_identity.current.account_id
  arn_prefix = "arn:${data.aws_partition.current.partition}:sqs:${var.region}:${local.account_id}"
  queue_arn  = "${local.arn_prefix}:${local.queue_name}"
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

resource "aws_sqs_queue" "dlq" {
  count = local.dlq_enabled ? 1 : 0

  name                              = local.dlq_name
  fifo_queue                        = var.fifo_queue
  content_based_deduplication       = var.fifo_queue ? var.content_based_deduplication : null
  message_retention_seconds         = var.dlq_message_retention_seconds
  max_message_size                  = var.max_message_size
  visibility_timeout_seconds        = var.visibility_timeout_seconds
  kms_master_key_id                 = var.kms_key_arn
  kms_data_key_reuse_period_seconds = var.kms_data_key_reuse_period_seconds

  tags = { Name = local.dlq_name }

  lifecycle {
    precondition {
      condition     = length(local.dlq_name) <= 80
      error_message = "The DLQ name (<Environment>-<name>-<dlq_name_suffix>[.fifo], currently \"${local.dlq_name}\") must be 80 characters or fewer."
    }
  }
}

resource "aws_sqs_queue" "this" {
  count = local.enabled ? 1 : 0

  name                              = local.queue_name
  fifo_queue                        = var.fifo_queue
  content_based_deduplication       = var.fifo_queue ? var.content_based_deduplication : null
  deduplication_scope               = var.deduplication_scope
  fifo_throughput_limit             = var.fifo_throughput_limit
  visibility_timeout_seconds        = var.visibility_timeout_seconds
  message_retention_seconds         = var.message_retention_seconds
  max_message_size                  = var.max_message_size
  delay_seconds                     = var.delay_seconds
  receive_wait_time_seconds         = var.receive_wait_time_seconds
  kms_master_key_id                 = var.kms_key_arn
  kms_data_key_reuse_period_seconds = var.kms_data_key_reuse_period_seconds

  redrive_policy = local.dlq_enabled ? jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq[0].arn
    maxReceiveCount     = var.dlq_max_receive_count
  }) : null

  tags = { Name = local.queue_name }

  lifecycle {
    precondition {
      condition     = length(local.queue_name) <= 80
      error_message = "The queue name (<Environment>-<name>[.fifo], currently \"${local.queue_name}\") must be 80 characters or fewer."
    }
  }
}

# Only this instance's queue may redrive into its DLQ (terraform-aws-modules/sqs
# create_dlq_redrive_allow_policy, on by default in Cloud Posse's component).
resource "aws_sqs_queue_redrive_allow_policy" "dlq" {
  count = local.dlq_enabled ? 1 : 0

  queue_url = aws_sqs_queue.dlq[0].id
  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [local.queue_arn]
  })
}

# Cloud Posse's queue policy: statements from iam_policy, each scoped to this
# queue and, by default, to this account (aws:SourceAccount).
data "aws_iam_policy_document" "queue" {
  count = local.policy_enabled ? 1 : 0

  policy_id = var.iam_policy[0].policy_id
  version   = var.iam_policy[0].version

  dynamic "statement" {
    for_each = var.iam_policy[0].statements

    content {
      sid         = statement.value.sid
      effect      = statement.value.effect
      actions     = statement.value.actions
      not_actions = statement.value.not_actions
      resources   = [local.queue_arn]

      dynamic "principals" {
        for_each = statement.value.principals
        content {
          type        = principals.value.type
          identifiers = principals.value.identifiers
        }
      }

      dynamic "not_principals" {
        for_each = statement.value.not_principals
        content {
          type        = not_principals.value.type
          identifiers = not_principals.value.identifiers
        }
      }

      # The account limit narrows Allow statements only (added to a Deny it
      # would make the Deny apply to fewer requests), and only those that do
      # not already set aws:SourceAccount themselves.
      dynamic "condition" {
        for_each = concat(
          statement.value.conditions,
          var.iam_policy_limit_to_current_account
          && coalesce(statement.value.effect, "Allow") == "Allow"
          && !contains([for c in statement.value.conditions : lower(c.variable)], "aws:sourceaccount") ? [{
            test     = "StringEquals"
            variable = "aws:SourceAccount"
            values   = [local.account_id]
          }] : []
        )
        content {
          test     = condition.value.test
          variable = condition.value.variable
          values   = condition.value.values
        }
      }
    }
  }
}

resource "aws_sqs_queue_policy" "this" {
  count = local.policy_enabled ? 1 : 0

  queue_url = aws_sqs_queue.this[0].id
  policy    = data.aws_iam_policy_document.queue[0].json
}
