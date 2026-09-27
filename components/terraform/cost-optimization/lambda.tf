# Log groups (created before their Lambda function, as in this repo's lambda
# component, to avoid circular dependencies and so the function's IAM policy
# can reference a real ARN - see iam.tf), the three Lambda functions
# themselves (packaged as a local zip via the archive provider, Cloud Posse
# aws-lambda style), their EventBridge schedules, and a CloudWatch alarm per
# function on its own Errors metric (each handler re-raises after logging
# rather than swallowing the exception into a 500 body, since EventBridge
# ignores a target Lambda's return value - only an unhandled exception
# increments Errors and can trigger an alarm).

# ========================================
# Instance Scheduler
# ========================================

resource "aws_cloudwatch_log_group" "scheduler" {
  count = local.current_settings.auto_shutdown ? 1 : 0

  name              = "/aws/lambda/${local.name}-scheduler"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = { Name = "/aws/lambda/${local.name}-scheduler" }
}

data "archive_file" "scheduler_lambda" {
  count = local.current_settings.auto_shutdown ? 1 : 0

  type        = "zip"
  output_path = "${path.module}/scheduler_lambda.zip"

  source {
    content  = file("${path.module}/lambda/scheduler.py")
    filename = "index.py"
  }
}

resource "aws_lambda_function" "scheduler" {
  count = local.current_settings.auto_shutdown ? 1 : 0

  function_name = "${local.name}-scheduler"
  role          = aws_iam_role.scheduler[0].arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 60
  memory_size   = 256

  environment {
    variables = {
      ENVIRONMENT = var.tags["Environment"]
      ACTION      = "START_STOP"
      TAG_FILTERS = jsonencode({
        Environment            = var.tags["Environment"]
        (local.opt_in_tag_key) = local.scheduler_opt_in_tag_value
      })
    }
  }

  filename         = data.archive_file.scheduler_lambda[0].output_path
  source_code_hash = data.archive_file.scheduler_lambda[0].output_base64sha256

  depends_on = [aws_cloudwatch_log_group.scheduler]

  tags = { Name = "${local.name}-scheduler" }
}

resource "aws_cloudwatch_metric_alarm" "scheduler_errors" {
  count = local.current_settings.auto_shutdown ? 1 : 0

  alarm_name          = "${local.name}-scheduler-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_description   = "The scheduler Lambda raised an unhandled exception (EventBridge invocations ignore return values, so only the Errors metric surfaces a failed run)."

  dimensions = {
    FunctionName = aws_lambda_function.scheduler[0].function_name
  }

  alarm_actions = [aws_sns_topic.cost_alerts.arn]
  ok_actions    = [aws_sns_topic.cost_alerts.arn]

  tags = { Name = "${local.name}-scheduler-errors" }
}

resource "aws_cloudwatch_event_rule" "start_instances" {
  count = local.current_settings.auto_shutdown && local.current_settings.schedule_on != null ? 1 : 0

  name                = "${local.name}-start-instances"
  description         = "Trigger instance start"
  schedule_expression = "cron(${local.current_settings.schedule_on})"

  tags = { Name = "${local.name}-start-instances" }
}

resource "aws_cloudwatch_event_rule" "stop_instances" {
  count = local.current_settings.auto_shutdown && local.current_settings.schedule_off != null ? 1 : 0

  name                = "${local.name}-stop-instances"
  description         = "Trigger instance stop"
  schedule_expression = "cron(${local.current_settings.schedule_off})"

  tags = { Name = "${local.name}-stop-instances" }
}

resource "aws_cloudwatch_event_target" "start_lambda" {
  count = local.current_settings.auto_shutdown && local.current_settings.schedule_on != null ? 1 : 0

  rule      = aws_cloudwatch_event_rule.start_instances[0].name
  target_id = "StartInstancesLambda"
  arn       = aws_lambda_function.scheduler[0].arn

  input = jsonencode({
    action = "START"
  })
}

resource "aws_cloudwatch_event_target" "stop_lambda" {
  count = local.current_settings.auto_shutdown && local.current_settings.schedule_off != null ? 1 : 0

  rule      = aws_cloudwatch_event_rule.stop_instances[0].name
  target_id = "StopInstancesLambda"
  arn       = aws_lambda_function.scheduler[0].arn

  input = jsonencode({
    action = "STOP"
  })
}

resource "aws_lambda_permission" "allow_cloudwatch_start" {
  count = local.current_settings.auto_shutdown && local.current_settings.schedule_on != null ? 1 : 0

  statement_id  = "AllowExecutionFromCloudWatchStart"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.scheduler[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.start_instances[0].arn
}

resource "aws_lambda_permission" "allow_cloudwatch_stop" {
  count = local.current_settings.auto_shutdown && local.current_settings.schedule_off != null ? 1 : 0

  statement_id  = "AllowExecutionFromCloudWatchStop"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.scheduler[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.stop_instances[0].arn
}

# ========================================
# Savings Plans / RI Recommendation Analyzer
# ========================================

resource "aws_cloudwatch_log_group" "savings_analyzer" {
  name              = "/aws/lambda/${local.name}-savings-analyzer"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = { Name = "/aws/lambda/${local.name}-savings-analyzer" }
}

data "archive_file" "savings_analyzer_lambda" {
  type        = "zip"
  output_path = "${path.module}/savings_analyzer_lambda.zip"

  source {
    content  = file("${path.module}/lambda/savings_analyzer.py")
    filename = "index.py"
  }
}

resource "aws_lambda_function" "savings_analyzer" {
  function_name = "${local.name}-savings-analyzer"
  role          = aws_iam_role.savings_analyzer.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 300
  memory_size   = 512

  environment {
    variables = {
      ENVIRONMENT = var.tags["Environment"]
      SNS_TOPIC   = aws_sns_topic.cost_alerts.arn
    }
  }

  filename         = data.archive_file.savings_analyzer_lambda.output_path
  source_code_hash = data.archive_file.savings_analyzer_lambda.output_base64sha256

  depends_on = [aws_cloudwatch_log_group.savings_analyzer]

  tags = { Name = "${local.name}-savings-analyzer" }
}

resource "aws_cloudwatch_metric_alarm" "savings_analyzer_errors" {
  alarm_name          = "${local.name}-savings-analyzer-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_description   = "The savings analyzer Lambda raised an unhandled exception (EventBridge invocations ignore return values, so only the Errors metric surfaces a failed run)."

  dimensions = {
    FunctionName = aws_lambda_function.savings_analyzer.function_name
  }

  alarm_actions = [aws_sns_topic.cost_alerts.arn]
  ok_actions    = [aws_sns_topic.cost_alerts.arn]

  tags = { Name = "${local.name}-savings-analyzer-errors" }
}

resource "aws_cloudwatch_event_rule" "savings_analysis" {
  name                = "${local.name}-savings-analysis"
  description         = "Weekly savings plan analysis"
  schedule_expression = "cron(0 9 ? * MON *)"

  tags = { Name = "${local.name}-savings-analysis" }
}

resource "aws_cloudwatch_event_target" "savings_analyzer_lambda" {
  rule      = aws_cloudwatch_event_rule.savings_analysis.name
  target_id = "SavingsAnalyzerLambda"
  arn       = aws_lambda_function.savings_analyzer.arn
}

resource "aws_lambda_permission" "allow_cloudwatch_savings" {
  statement_id  = "AllowExecutionFromCloudWatchSavings"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.savings_analyzer.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.savings_analysis.arn
}

# ========================================
# Unused Resource Cleanup
# ========================================

resource "aws_cloudwatch_log_group" "resource_cleanup" {
  name              = "/aws/lambda/${local.name}-resource-cleanup"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = { Name = "/aws/lambda/${local.name}-resource-cleanup" }
}

data "archive_file" "cleanup_lambda" {
  type        = "zip"
  output_path = "${path.module}/cleanup_lambda.zip"

  source {
    content  = file("${path.module}/lambda/cleanup.py")
    filename = "index.py"
  }
}

resource "aws_lambda_function" "resource_cleanup" {
  function_name = "${local.name}-resource-cleanup"
  role          = aws_iam_role.resource_cleanup.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 300
  memory_size   = 512

  environment {
    variables = {
      ENVIRONMENT             = var.tags["Environment"]
      DRY_RUN                 = var.cleanup_dry_run
      SNS_TOPIC               = aws_sns_topic.cost_alerts.arn
      CLEANUP_UNUSED_VOLUMES  = tostring(var.cleanup_unused_volumes)
      CLEANUP_OLD_SNAPSHOTS   = tostring(var.cleanup_old_snapshots)
      CLEANUP_UNUSED_EIPS     = tostring(var.cleanup_unused_eips)
      SNAPSHOT_RETENTION_DAYS = tostring(var.snapshot_retention_days)
      TAG_KEY                 = local.opt_in_tag_key
      TAG_VALUE               = local.cleanup_opt_in_tag_value
    }
  }

  filename         = data.archive_file.cleanup_lambda.output_path
  source_code_hash = data.archive_file.cleanup_lambda.output_base64sha256

  depends_on = [aws_cloudwatch_log_group.resource_cleanup]

  tags = { Name = "${local.name}-resource-cleanup" }
}

resource "aws_cloudwatch_metric_alarm" "resource_cleanup_errors" {
  alarm_name          = "${local.name}-resource-cleanup-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_description   = "The resource cleanup Lambda raised an unhandled exception (EventBridge invocations ignore return values, so only the Errors metric surfaces a failed run)."

  dimensions = {
    FunctionName = aws_lambda_function.resource_cleanup.function_name
  }

  alarm_actions = [aws_sns_topic.cost_alerts.arn]
  ok_actions    = [aws_sns_topic.cost_alerts.arn]

  tags = { Name = "${local.name}-resource-cleanup-errors" }
}

resource "aws_cloudwatch_event_rule" "cleanup" {
  name                = "${local.name}-resource-cleanup"
  description         = "Weekly unused resource cleanup"
  schedule_expression = "cron(0 2 ? * SUN *)"

  tags = { Name = "${local.name}-resource-cleanup" }
}

resource "aws_cloudwatch_event_target" "cleanup_lambda" {
  rule      = aws_cloudwatch_event_rule.cleanup.name
  target_id = "CleanupLambda"
  arn       = aws_lambda_function.resource_cleanup.arn
}

resource "aws_lambda_permission" "allow_cloudwatch_cleanup" {
  statement_id  = "AllowExecutionFromCloudWatchCleanup"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.resource_cleanup.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.cleanup.arn
}
