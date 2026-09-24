# One EventBridge rule per instance that delivers matched events to a
# CloudWatch log group, as Cloud Posse's aws-eventbridge component does (it
# wraps cloudposse/cloudwatch-logs and cloudposse/cloudwatch-events). Written
# as plain resources, like the other root components. Added for this repo: an
# optional custom bus with an archive, and KMS encryption throughout.

locals {
  enabled     = var.enabled
  name        = "${var.tags["Environment"]}-${var.name}"
  description = var.cloudwatch_event_rule_description != "" ? var.cloudwatch_event_rule_description : local.name

  create_bus     = local.enabled && var.create_event_bus
  event_bus_name = local.create_bus ? aws_cloudwatch_event_bus.this[0].name : var.event_bus_name
}

resource "aws_cloudwatch_event_bus" "this" {
  count = local.create_bus ? 1 : 0

  name               = local.name
  description        = local.description
  kms_key_identifier = var.kms_key_arn

  dynamic "dead_letter_config" {
    for_each = var.event_bus_dlq_arn != null ? [var.event_bus_dlq_arn] : []

    content {
      arn = dead_letter_config.value
    }
  }

  tags = { Name = local.name }
}

resource "aws_cloudwatch_event_archive" "this" {
  count = local.create_bus && var.archive_enabled ? 1 : 0

  name               = local.name
  description        = "Every event on ${local.name}, kept for replay"
  event_source_arn   = aws_cloudwatch_event_bus.this[0].arn
  retention_days     = var.archive_retention_days
  kms_key_identifier = var.kms_key_arn

  lifecycle {
    precondition {
      # AWS caps archive names at 48 characters; name is capped at 30 in
      # variables.tf, which only covers this with Environment <= 17 characters.
      condition     = length(local.name) <= 48
      error_message = "The archive name (<Environment>-<name>, currently \"${local.name}\") must be 48 characters or fewer."
    }
  }
}

# EventBridge only delivers to log groups under /aws/events/.
resource "aws_cloudwatch_log_group" "this" {
  # checkov:skip=CKV_AWS_338:Retention mirrors Cloud Posse's aws-eventbridge (3 days) and is a per-stack cost decision (event_log_retention_in_days), as on the repo's other log groups.
  count = local.enabled ? 1 : 0

  name              = "/aws/events/${local.name}"
  retention_in_days = var.event_log_retention_in_days
  kms_key_id        = var.kms_key_arn

  tags = { Name = "/aws/events/${local.name}" }
}

resource "aws_cloudwatch_event_rule" "this" {
  count = local.enabled ? 1 : 0

  name           = local.name
  description    = local.description
  event_bus_name = local.event_bus_name
  event_pattern  = jsonencode(var.cloudwatch_event_rule_pattern)
  state          = "ENABLED"

  tags = { Name = local.name }
}

resource "aws_cloudwatch_event_target" "logs" {
  count = local.enabled ? 1 : 0

  rule           = aws_cloudwatch_event_rule.this[0].name
  event_bus_name = local.event_bus_name
  target_id      = "cloudwatch-logs"
  arn            = aws_cloudwatch_log_group.this[0].arn
}

data "aws_caller_identity" "current" {}

# EventBridge writes to the log group under a resource policy, not a role
# (Cloud Posse's policies.tf).
data "aws_iam_policy_document" "logs" {
  count = local.enabled ? 1 : 0

  statement {
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com", "delivery.logs.amazonaws.com"]
    }
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.this[0].arn}:*"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

# Deviation from Cloud Posse: a resource-scoped policy (resource_arn, provider
# >= 6.36) instead of an account-scoped one (policy_name). Account-scoped
# policies are capped at 10 per region, shared with every other component and
# service in the account; a resource-scoped policy is attached to this log
# group alone and consumes none of that quota. aws_cloudwatch_log_group.arn
# already has the API's trailing `:*` stripped (see its docs), which is the
# format `resource_arn` requires here.
resource "aws_cloudwatch_log_resource_policy" "this" {
  count = local.enabled ? 1 : 0

  resource_arn    = aws_cloudwatch_log_group.this[0].arn
  policy_document = data.aws_iam_policy_document.logs[0].json
}
