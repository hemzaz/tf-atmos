# One EventBridge rule per instance that delivers matched events to a
# CloudWatch log group, as Cloud Posse's aws-eventbridge component does (it
# wraps cloudposse/cloudwatch-logs and cloudposse/cloudwatch-events). Written
# as plain resources, like the other root components. Added for this repo: an
# optional custom bus with an archive, KMS encryption throughout, and further
# targets (queues, topics, functions, ...) next to the log group.

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

# The rule's other targets (var.targets), as Cloud Posse's cloudwatch-events
# module creates its one target. SQS and SNS targets need their own resource
# policy to let events.amazonaws.com send from this rule; see the README.
resource "aws_cloudwatch_event_target" "this" {
  for_each = local.enabled ? var.targets : {}

  rule           = aws_cloudwatch_event_rule.this[0].name
  event_bus_name = local.event_bus_name
  target_id      = each.key
  arn            = each.value.arn
  role_arn       = each.value.role_arn
  input_path     = each.value.input_path

  dynamic "input_transformer" {
    for_each = each.value.input_transformer != null ? [each.value.input_transformer] : []

    content {
      input_paths    = input_transformer.value.input_paths
      input_template = input_transformer.value.input_template
    }
  }

  dynamic "dead_letter_config" {
    for_each = each.value.dead_letter_config != null ? [each.value.dead_letter_config] : []

    content {
      arn = dead_letter_config.value.arn
    }
  }

  dynamic "retry_policy" {
    for_each = each.value.retry_policy != null ? [each.value.retry_policy] : []

    content {
      maximum_event_age_in_seconds = retry_policy.value.maximum_event_age_in_seconds
      maximum_retry_attempts       = retry_policy.value.maximum_retry_attempts
    }
  }

  dynamic "ecs_target" {
    for_each = each.value.ecs_target != null ? [each.value.ecs_target] : []

    content {
      task_definition_arn     = ecs_target.value.task_definition_arn
      task_count              = ecs_target.value.task_count
      launch_type             = ecs_target.value.launch_type
      platform_version        = ecs_target.value.platform_version
      group                   = ecs_target.value.group
      enable_ecs_managed_tags = ecs_target.value.enable_ecs_managed_tags
      enable_execute_command  = ecs_target.value.enable_execute_command
      propagate_tags          = ecs_target.value.propagate_tags

      dynamic "network_configuration" {
        for_each = ecs_target.value.network_configuration != null ? [ecs_target.value.network_configuration] : []

        content {
          subnets          = network_configuration.value.subnets
          security_groups  = network_configuration.value.security_groups
          assign_public_ip = network_configuration.value.assign_public_ip
        }
      }
    }
  }

  dynamic "batch_target" {
    for_each = each.value.batch_target != null ? [each.value.batch_target] : []

    content {
      job_definition = batch_target.value.job_definition
      job_name       = batch_target.value.job_name
      array_size     = batch_target.value.array_size
      job_attempts   = batch_target.value.job_attempts
    }
  }

  dynamic "sqs_target" {
    for_each = each.value.sqs_message_group_id != null ? [each.value.sqs_message_group_id] : []

    content {
      message_group_id = sqs_target.value
    }
  }
}

# A Lambda target is invoked under the function's resource policy: let
# events.amazonaws.com invoke it from this rule only.
resource "aws_lambda_permission" "this" {
  for_each = local.enabled ? {
    for k, t in var.targets : k => t.arn
    if split(":", t.arn)[2] == "lambda" && strcontains(t.arn, ":function:")
  } : {}

  # Statement IDs take letters, digits, hyphen and underscore only.
  statement_id  = replace("AllowEventBridge-${local.name}-${each.key}", ".", "_")
  action        = "lambda:InvokeFunction"
  function_name = each.value
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.this[0].arn

  lifecycle {
    precondition {
      condition     = length("AllowEventBridge-${local.name}-${each.key}") <= 100
      error_message = "The Lambda permission statement ID (AllowEventBridge-<Environment>-<name>-<target key>) must be 100 characters or fewer: shorten the target key."
    }
  }
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
