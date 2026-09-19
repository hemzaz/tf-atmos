##############################################
# EventBridge Event Bus
##############################################

locals {
  bus_name = "${var.name_prefix}-${var.bus_name}"

  tags = merge(
    var.tags,
    {
      Name      = local.bus_name
      ManagedBy = "Terraform"
    }
  )
}

##############################################
# Custom Event Bus
##############################################

resource "aws_cloudwatch_event_bus" "main" {
  name = local.bus_name

  tags = local.tags
}

##############################################
# Event Bus Policy for Cross-Account
##############################################

resource "aws_cloudwatch_event_bus_policy" "main" {
  count = var.event_bus_policy != null || length(var.allowed_accounts) > 0 ? 1 : 0

  event_bus_name = aws_cloudwatch_event_bus.main.name
  policy         = var.event_bus_policy != null ? var.event_bus_policy : data.aws_iam_policy_document.event_bus[0].json
}

data "aws_iam_policy_document" "event_bus" {
  count = var.event_bus_policy == null && length(var.allowed_accounts) > 0 ? 1 : 0

  statement {
    sid    = "AllowAccountsToPutEvents"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [for account in var.allowed_accounts : "arn:aws:iam::${account}:root"]
    }

    actions   = ["events:PutEvents"]
    resources = [aws_cloudwatch_event_bus.main.arn]
  }
}

##############################################
# Event Archive
##############################################

resource "aws_cloudwatch_event_archive" "main" {
  for_each = var.enable_archive ? { archive = var.archive_config } : {}

  name             = "${local.bus_name}-archive"
  event_source_arn = aws_cloudwatch_event_bus.main.arn
  description      = coalesce(each.value.description, "Event archive for ${local.bus_name}")
  retention_days   = each.value.retention_days
  event_pattern    = each.value.event_pattern
}

##############################################
# Event Rules
##############################################

resource "aws_cloudwatch_event_rule" "main" {
  for_each = { for rule in var.event_rules : rule.name => rule }

  name                = "${local.bus_name}-${each.value.name}"
  description         = each.value.description
  event_bus_name      = aws_cloudwatch_event_bus.main.name
  event_pattern       = each.value.event_pattern
  schedule_expression = each.value.schedule_expression
  state               = each.value.enabled ? "ENABLED" : "DISABLED"
  role_arn            = each.value.role_arn

  tags = merge(
    local.tags,
    each.value.tags
  )
}

##############################################
# Lambda Targets
##############################################

resource "aws_cloudwatch_event_target" "lambda" {
  for_each = { for target in local.lambda_targets : target.key => target }

  rule           = aws_cloudwatch_event_rule.main[each.value.rule_name].name
  event_bus_name = aws_cloudwatch_event_bus.main.name
  arn            = each.value.function_arn
  target_id      = coalesce(each.value.target_id, "lambda-${each.key}")

  dynamic "input_transformer" {
    for_each = each.value.input_transformer != null ? [each.value.input_transformer] : []
    content {
      input_paths    = input_transformer.value.input_paths
      input_template = input_transformer.value.input_template
    }
  }

  dynamic "dead_letter_config" {
    for_each = each.value.dlq_arn != null ? [1] : []
    content {
      arn = each.value.dlq_arn
    }
  }

  dynamic "retry_policy" {
    for_each = each.value.retry_policy != null ? [each.value.retry_policy] : []
    content {
      maximum_event_age_in_seconds = retry_policy.value.maximum_event_age
      maximum_retry_attempts       = retry_policy.value.maximum_retry_attempts
    }
  }
}

##############################################
# SQS Targets
##############################################

resource "aws_cloudwatch_event_target" "sqs" {
  for_each = { for target in local.sqs_targets : target.key => target }

  rule           = aws_cloudwatch_event_rule.main[each.value.rule_name].name
  event_bus_name = aws_cloudwatch_event_bus.main.name
  arn            = each.value.queue_arn
  target_id      = coalesce(each.value.target_id, "sqs-${each.key}")

  dynamic "sqs_target" {
    for_each = each.value.message_group_id != null ? [1] : []
    content {
      message_group_id = each.value.message_group_id
    }
  }

  dynamic "dead_letter_config" {
    for_each = each.value.dlq_arn != null ? [1] : []
    content {
      arn = each.value.dlq_arn
    }
  }
}

##############################################
# Step Functions Targets
##############################################

resource "aws_cloudwatch_event_target" "step_functions" {
  for_each = { for target in local.step_functions_targets : target.key => target }

  rule           = aws_cloudwatch_event_rule.main[each.value.rule_name].name
  event_bus_name = aws_cloudwatch_event_bus.main.name
  arn            = each.value.state_machine_arn
  target_id      = coalesce(each.value.target_id, "sfn-${each.key}")
  role_arn       = each.value.role_arn

  dynamic "dead_letter_config" {
    for_each = each.value.dlq_arn != null ? [1] : []
    content {
      arn = each.value.dlq_arn
    }
  }
}

##############################################
# Kinesis Targets
##############################################

resource "aws_cloudwatch_event_target" "kinesis" {
  for_each = { for target in local.kinesis_targets : target.key => target }

  rule           = aws_cloudwatch_event_rule.main[each.value.rule_name].name
  event_bus_name = aws_cloudwatch_event_bus.main.name
  arn            = each.value.stream_arn
  target_id      = coalesce(each.value.target_id, "kinesis-${each.key}")
  role_arn       = each.value.role_arn

  dynamic "kinesis_target" {
    for_each = each.value.partition_key_path != null ? [1] : []
    content {
      partition_key_path = each.value.partition_key_path
    }
  }
}

##############################################
# SNS Targets
##############################################

resource "aws_cloudwatch_event_target" "sns" {
  for_each = { for target in local.sns_targets : target.key => target }

  rule           = aws_cloudwatch_event_rule.main[each.value.rule_name].name
  event_bus_name = aws_cloudwatch_event_bus.main.name
  arn            = each.value.topic_arn
  target_id      = coalesce(each.value.target_id, "sns-${each.key}")

  dynamic "dead_letter_config" {
    for_each = each.value.dlq_arn != null ? [1] : []
    content {
      arn = each.value.dlq_arn
    }
  }
}

##############################################
# EventBridge Bus Targets (Cross-Bus)
##############################################

resource "aws_cloudwatch_event_target" "event_bus" {
  for_each = { for target in local.event_bus_targets : target.key => target }

  rule           = aws_cloudwatch_event_rule.main[each.value.rule_name].name
  event_bus_name = aws_cloudwatch_event_bus.main.name
  arn            = each.value.event_bus_arn
  target_id      = coalesce(each.value.target_id, "bus-${each.key}")
  role_arn       = each.value.role_arn
}

##############################################
# Schema Registry
##############################################

resource "aws_schemas_registry" "main" {
  count = var.enable_schema_registry ? 1 : 0

  name        = "${local.bus_name}-registry"
  description = "Schema registry for ${local.bus_name}"

  tags = local.tags
}

resource "aws_schemas_discoverer" "main" {
  count = var.enable_schema_discovery ? 1 : 0

  source_arn  = aws_cloudwatch_event_bus.main.arn
  description = "Schema discoverer for ${local.bus_name}"

  tags = local.tags
}

##############################################
# CloudWatch Alarms
##############################################

resource "aws_cloudwatch_metric_alarm" "failed_invocations" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.bus_name}-failed-invocations"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "FailedInvocations"
  namespace           = "AWS/Events"
  period              = var.alarm_period_seconds
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Failed event invocations for ${local.bus_name}"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.alarm_ok_actions

  dimensions = {
    EventBusName = aws_cloudwatch_event_bus.main.name
  }

  tags = local.tags
}

##############################################
# Local Variables for Target Processing
##############################################

locals {
  lambda_targets = flatten([
    for rule in var.event_rules : [
      for idx, target in rule.lambda_targets : merge(target, {
        rule_name = rule.name
        key       = "${rule.name}-${idx}"
      })
    ]
  ])

  sqs_targets = flatten([
    for rule in var.event_rules : [
      for idx, target in rule.sqs_targets : merge(target, {
        rule_name = rule.name
        key       = "${rule.name}-${idx}"
      })
    ]
  ])

  step_functions_targets = flatten([
    for rule in var.event_rules : [
      for idx, target in rule.step_functions_targets : merge(target, {
        rule_name = rule.name
        key       = "${rule.name}-${idx}"
      })
    ]
  ])

  kinesis_targets = flatten([
    for rule in var.event_rules : [
      for idx, target in rule.kinesis_targets : merge(target, {
        rule_name = rule.name
        key       = "${rule.name}-${idx}"
      })
    ]
  ])

  sns_targets = flatten([
    for rule in var.event_rules : [
      for idx, target in rule.sns_targets : merge(target, {
        rule_name = rule.name
        key       = "${rule.name}-${idx}"
      })
    ]
  ])

  event_bus_targets = flatten([
    for rule in var.event_rules : [
      for idx, target in rule.event_bus_targets : merge(target, {
        rule_name = rule.name
        key       = "${rule.name}-${idx}"
      })
    ]
  ])
}
