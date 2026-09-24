locals {
  name_prefix = "${var.tags["Environment"]}-${lookup(var.tags, "Name", "security")}"

  # The detector and the hub are owned by the guardduty and securityhub
  # components (one component per service, the Cloud Posse model). This
  # component only routes their findings, so a null ID turns the matching
  # EventBridge rule and alarm off. Both are plain variables, so the counts
  # below are known at plan time.
  guardduty_enabled    = var.guardduty_detector_id != null
  security_hub_enabled = var.securityhub_account_arn != null
}

# AWS Inspector V2
resource "aws_inspector2_enabler" "main" {
  count = var.enable_inspector ? 1 : 0

  account_ids    = [data.aws_caller_identity.current.account_id]
  resource_types = var.inspector_resource_types
}

# SNS Topic for Security Alerts
resource "aws_sns_topic" "security_alerts" {
  name              = "${local.name_prefix}-alerts"
  display_name      = "Security Alerts for ${var.tags["Environment"]}"
  kms_master_key_id = var.kms_key_id

  tags = { Name = "${local.name_prefix}-alerts" }
}

resource "aws_sns_topic_policy" "security_alerts" {
  arn = aws_sns_topic.security_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEventBridgeToPublish"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.security_alerts.arn
      },
      {
        Sid    = "AllowCloudWatchToPublish"
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.security_alerts.arn
      }
    ]
  })
}

# Email subscriptions for security alerts
resource "aws_sns_topic_subscription" "security_email" {
  count = length(var.security_email_subscriptions)

  topic_arn = aws_sns_topic.security_alerts.arn
  protocol  = "email"
  endpoint  = var.security_email_subscriptions[count.index]
}

# EventBridge rule for GuardDuty findings
resource "aws_cloudwatch_event_rule" "guardduty_findings" {
  count = local.guardduty_enabled ? 1 : 0

  name        = "${local.name_prefix}-guardduty-findings"
  description = "Capture GuardDuty MEDIUM, HIGH and CRITICAL findings (severity 4.0 and above)"

  # Numeric matching, not an enumerated list: GuardDuty severities are decimals
  # and CRITICAL attack sequences score 9.0-10.0, which a list ending at 8.9
  # silently dropped. LOW findings (1.0-3.9) stay in the console only.
  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail = {
      severity = [{ numeric = [">=", 4] }]
    }
  })
}

resource "aws_cloudwatch_event_target" "guardduty_sns" {
  count = local.guardduty_enabled ? 1 : 0

  rule      = aws_cloudwatch_event_rule.guardduty_findings[0].name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.security_alerts.arn
}

# EventBridge rule for Security Hub findings
resource "aws_cloudwatch_event_rule" "securityhub_findings" {
  count = local.security_hub_enabled ? 1 : 0

  name        = "${local.name_prefix}-securityhub-findings"
  description = "Capture Security Hub HIGH and CRITICAL findings"

  event_pattern = jsonencode({
    source      = ["aws.securityhub"]
    detail-type = ["Security Hub Findings - Imported"]
    detail = {
      findings = {
        Severity = {
          Label = ["HIGH", "CRITICAL"]
        }
        Compliance = {
          Status = ["FAILED"]
        }
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "securityhub_sns" {
  count = local.security_hub_enabled ? 1 : 0

  rule      = aws_cloudwatch_event_rule.securityhub_findings[0].name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.security_alerts.arn
}

# EventBridge rule for Inspector findings
resource "aws_cloudwatch_event_rule" "inspector_findings" {
  count = var.enable_inspector ? 1 : 0

  name        = "${local.name_prefix}-inspector-findings"
  description = "Capture Inspector HIGH and CRITICAL findings"

  event_pattern = jsonencode({
    source      = ["aws.inspector2"]
    detail-type = ["Inspector2 Finding"]
    detail = {
      severity = ["HIGH", "CRITICAL"]
    }
  })
}

resource "aws_cloudwatch_event_target" "inspector_sns" {
  count = var.enable_inspector ? 1 : 0

  rule      = aws_cloudwatch_event_rule.inspector_findings[0].name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.security_alerts.arn
}

# Lambda function for alert enrichment
resource "aws_lambda_function" "alert_enrichment" {
  count = var.enable_alert_enrichment ? 1 : 0

  filename      = "${path.module}/lambda/alert-enrichment.zip"
  function_name = "${local.name_prefix}-alert-enrichment"
  role          = aws_iam_role.alert_enrichment[0].arn
  handler       = "index.handler"
  # The package is not committed; try() keeps the disabled path valid and the precondition
  # below reports a missing package when the function is enabled.
  source_code_hash = try(filebase64sha256("${path.module}/lambda/alert-enrichment.zip"), null)
  runtime          = "python3.11"
  timeout          = 60
  memory_size      = 256

  environment {
    variables = {
      SLACK_WEBHOOK_URL = var.slack_webhook_url != null ? var.slack_webhook_url : ""
      PAGERDUTY_API_KEY = var.pagerduty_integration_key != null ? var.pagerduty_integration_key : ""
      ENVIRONMENT       = var.tags["Environment"]
    }
  }


  lifecycle {
    precondition {
      condition     = fileexists("${path.module}/lambda/alert-enrichment.zip")
      error_message = "Lambda package ${path.module}/lambda/alert-enrichment.zip is missing; build it before enabling this function."
    }
  }
}

# IAM role for alert enrichment Lambda
resource "aws_iam_role" "alert_enrichment" {
  count = var.enable_alert_enrichment ? 1 : 0

  name = "${local.name_prefix}-alert-enrichment-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "alert_enrichment_basic" {
  count = var.enable_alert_enrichment ? 1 : 0

  role       = aws_iam_role.alert_enrichment[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "alert_enrichment_custom" {
  count = var.enable_alert_enrichment ? 1 : 0

  name = "${local.name_prefix}-alert-enrichment-policy"
  role = aws_iam_role.alert_enrichment[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "guardduty:GetFindings",
          "securityhub:GetFindings",
          "inspector2:GetFindings",
          "ec2:DescribeInstances",
          "ecs:DescribeTasks",
          "eks:DescribeCluster"
        ]
        Resource = "*"
      }
    ]
  })
}

# Subscribe Lambda to SNS topic
resource "aws_sns_topic_subscription" "alert_enrichment" {
  count = var.enable_alert_enrichment ? 1 : 0

  topic_arn = aws_sns_topic.security_alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.alert_enrichment[0].arn
}

resource "aws_lambda_permission" "alert_enrichment_sns" {
  count = var.enable_alert_enrichment ? 1 : 0

  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.alert_enrichment[0].function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.security_alerts.arn
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "alert_enrichment" {
  count = var.enable_alert_enrichment ? 1 : 0

  name              = "/aws/lambda/${local.name_prefix}-alert-enrichment"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_id
}

# CloudWatch alarms for security events
resource "aws_cloudwatch_metric_alarm" "guardduty_high_findings" {
  count = local.guardduty_enabled ? 1 : 0

  alarm_name          = "${local.name_prefix}-guardduty-high-findings"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "HighSeverityFindings"
  namespace           = "AWS/GuardDuty"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.guardduty_finding_threshold
  alarm_description   = "GuardDuty high severity findings detected"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]
  treat_missing_data  = "notBreaching"
}

# Root account usage alarm
resource "aws_cloudwatch_metric_alarm" "root_account_usage" {
  alarm_name          = "${local.name_prefix}-root-account-usage"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "RootAccountUsage"
  namespace           = "CloudTrailMetrics"
  period              = "60"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "Root account has been used"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]
  treat_missing_data  = "notBreaching"
}

# Unauthorized API calls alarm
resource "aws_cloudwatch_metric_alarm" "unauthorized_api_calls" {
  alarm_name          = "${local.name_prefix}-unauthorized-api-calls"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "UnauthorizedAPICalls"
  namespace           = "CloudTrailMetrics"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.unauthorized_api_threshold
  alarm_description   = "Unauthorized API calls detected"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]
  treat_missing_data  = "notBreaching"
}

# IAM policy changes alarm
resource "aws_cloudwatch_metric_alarm" "iam_policy_changes" {
  alarm_name          = "${local.name_prefix}-iam-policy-changes"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "IAMPolicyChanges"
  namespace           = "CloudTrailMetrics"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.iam_changes_threshold
  alarm_description   = "IAM policy changes detected"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]
  treat_missing_data  = "notBreaching"
}

# Security group changes alarm
resource "aws_cloudwatch_metric_alarm" "security_group_changes" {
  alarm_name          = "${local.name_prefix}-security-group-changes"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "SecurityGroupChanges"
  namespace           = "CloudTrailMetrics"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.sg_changes_threshold
  alarm_description   = "Security group changes detected"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]
  treat_missing_data  = "notBreaching"
}

# Data source for current AWS account
data "aws_caller_identity" "current" {}
