##############################################
# Step Functions State Machine
##############################################

locals {
  state_machine_name = "${var.name_prefix}-${var.state_machine_name}"
  log_group_name     = "/aws/vendedlogs/states/${local.state_machine_name}"

  tags = merge(
    var.tags,
    {
      Name      = local.state_machine_name
      ManagedBy = "Terraform"
    }
  )
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

##############################################
# CloudWatch Log Group
##############################################

resource "aws_cloudwatch_log_group" "main" {
  count = var.enable_logging ? 1 : 0

  name              = local.log_group_name
  retention_in_days = var.log_retention_days
  kms_key_id        = var.log_kms_key_id

  tags = local.tags
}

##############################################
# IAM Role for State Machine
##############################################

resource "aws_iam_role" "state_machine" {
  name               = "${local.state_machine_name}-execution"
  assume_role_policy = data.aws_iam_policy_document.state_machine_assume.json

  tags = local.tags
}

data "aws_iam_policy_document" "state_machine_assume" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

##############################################
# IAM Policy for State Machine
##############################################

resource "aws_iam_role_policy" "state_machine" {
  name   = "state-machine-execution"
  role   = aws_iam_role.state_machine.id
  policy = data.aws_iam_policy_document.state_machine_policy.json
}

data "aws_iam_policy_document" "state_machine_policy" {
  # CloudWatch Logs
  dynamic "statement" {
    for_each = var.enable_logging ? [1] : []
    content {
      effect = "Allow"
      actions = [
        "logs:CreateLogDelivery",
        "logs:GetLogDelivery",
        "logs:UpdateLogDelivery",
        "logs:DeleteLogDelivery",
        "logs:ListLogDeliveries",
        "logs:PutResourcePolicy",
        "logs:DescribeResourcePolicies",
        "logs:DescribeLogGroups"
      ]
      resources = ["*"]
    }
  }

  # X-Ray
  dynamic "statement" {
    for_each = var.enable_xray_tracing ? [1] : []
    content {
      effect = "Allow"
      actions = [
        "xray:PutTraceSegments",
        "xray:PutTelemetryRecords",
        "xray:GetSamplingRules",
        "xray:GetSamplingTargets"
      ]
      resources = ["*"]
    }
  }

  # Lambda invocation
  dynamic "statement" {
    for_each = length(var.lambda_function_arns) > 0 ? [1] : []
    content {
      effect = "Allow"
      actions = [
        "lambda:InvokeFunction"
      ]
      resources = var.lambda_function_arns
    }
  }

  # SQS
  dynamic "statement" {
    for_each = length(var.sqs_queue_arns) > 0 ? [1] : []
    content {
      effect = "Allow"
      actions = [
        "sqs:SendMessage"
      ]
      resources = var.sqs_queue_arns
    }
  }

  # SNS
  dynamic "statement" {
    for_each = length(var.sns_topic_arns) > 0 ? [1] : []
    content {
      effect = "Allow"
      actions = [
        "sns:Publish"
      ]
      resources = var.sns_topic_arns
    }
  }

  # DynamoDB
  dynamic "statement" {
    for_each = length(var.dynamodb_table_arns) > 0 ? [1] : []
    content {
      effect = "Allow"
      actions = [
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem",
        "dynamodb:GetItem",
        "dynamodb:Query",
        "dynamodb:Scan"
      ]
      resources = var.dynamodb_table_arns
    }
  }

  # ECS
  dynamic "statement" {
    for_each = length(var.ecs_task_arns) > 0 ? [1] : []
    content {
      effect = "Allow"
      actions = [
        "ecs:RunTask"
      ]
      resources = var.ecs_task_arns
    }
  }

  dynamic "statement" {
    for_each = length(var.ecs_task_arns) > 0 ? [1] : []
    content {
      effect = "Allow"
      actions = [
        "ecs:StopTask",
        "ecs:DescribeTasks"
      ]
      resources = ["*"]
      condition {
        test     = "ArnEquals"
        variable = "ecs:cluster"
        values   = var.ecs_cluster_arns
      }
    }
  }

  dynamic "statement" {
    for_each = length(var.ecs_task_execution_role_arns) > 0 ? [1] : []
    content {
      effect = "Allow"
      actions = [
        "iam:PassRole"
      ]
      resources = var.ecs_task_execution_role_arns
    }
  }

  # EventBridge
  dynamic "statement" {
    for_each = length(var.eventbridge_bus_arns) > 0 ? [1] : []
    content {
      effect = "Allow"
      actions = [
        "events:PutEvents"
      ]
      resources = var.eventbridge_bus_arns
    }
  }

  # Additional custom policies
  dynamic "statement" {
    for_each = var.additional_policy_statements
    content {
      sid       = lookup(statement.value, "sid", null)
      effect    = statement.value.effect
      actions   = statement.value.actions
      resources = statement.value.resources
      dynamic "condition" {
        for_each = lookup(statement.value, "conditions", [])
        content {
          test     = condition.value.test
          variable = condition.value.variable
          values   = condition.value.values
        }
      }
    }
  }
}

##############################################
# State Machine
##############################################

resource "aws_sfn_state_machine" "main" {
  name     = local.state_machine_name
  role_arn = aws_iam_role.state_machine.arn

  definition = var.definition
  type       = var.state_machine_type

  dynamic "logging_configuration" {
    for_each = var.enable_logging ? [1] : []
    content {
      log_destination        = "${aws_cloudwatch_log_group.main[0].arn}:*"
      include_execution_data = var.log_include_execution_data
      level                  = var.log_level
    }
  }

  dynamic "tracing_configuration" {
    for_each = var.enable_xray_tracing ? [1] : []
    content {
      enabled = true
    }
  }

  tags = local.tags
}

##############################################
# CloudWatch Alarms
##############################################

resource "aws_cloudwatch_metric_alarm" "execution_failed" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.state_machine_name}-execution-failed"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "ExecutionsFailed"
  namespace           = "AWS/States"
  period              = var.alarm_period_seconds
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Step Functions execution failures for ${local.state_machine_name}"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.alarm_ok_actions

  dimensions = {
    StateMachineArn = aws_sfn_state_machine.main.arn
  }

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "execution_throttled" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.state_machine_name}-execution-throttled"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "ExecutionThrottled"
  namespace           = "AWS/States"
  period              = var.alarm_period_seconds
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Step Functions execution throttled for ${local.state_machine_name}"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.alarm_ok_actions

  dimensions = {
    StateMachineArn = aws_sfn_state_machine.main.arn
  }

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "execution_timed_out" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.state_machine_name}-execution-timed-out"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "ExecutionsTimedOut"
  namespace           = "AWS/States"
  period              = var.alarm_period_seconds
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Step Functions execution timeouts for ${local.state_machine_name}"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.alarm_ok_actions

  dimensions = {
    StateMachineArn = aws_sfn_state_machine.main.arn
  }

  tags = local.tags
}
