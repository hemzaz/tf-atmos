locals {
  name_prefix = "${var.tags["Environment"]}-${var.tags["Name"] != null ? var.tags["Name"] : "security"}"
}

# GuardDuty Detector
resource "aws_guardduty_detector" "main" {
  enable = var.enable_guardduty

  datasources {
    s3_logs {
      enable = var.enable_s3_protection
    }
    kubernetes {
      audit_logs {
        enable = var.enable_eks_protection
      }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          enable = var.enable_malware_protection
        }
      }
    }
  }

  finding_publishing_frequency = var.guardduty_finding_frequency

  tags = merge(
    var.tags,
    {
      Name = "${local.name_prefix}-detector"
    }
  )
}

# GuardDuty Filter for high/critical findings
resource "aws_guardduty_filter" "high_severity" {
  count = var.enable_guardduty ? 1 : 0

  name        = "${local.name_prefix}-high-severity-findings"
  action      = "ARCHIVE"
  detector_id = aws_guardduty_detector.main.id
  rank        = 1

  finding_criteria {
    criterion {
      field  = "severity"
      equals = ["0", "1", "2", "3"]
    }
  }
}

# Security Hub
resource "aws_securityhub_account" "main" {
  count = var.enable_security_hub ? 1 : 0

  enable_default_standards = var.enable_default_standards
  control_finding_generator = "SECURITY_CONTROL"
  auto_enable_controls      = var.auto_enable_controls
}

# Enable CIS AWS Foundations Benchmark
resource "aws_securityhub_standards_subscription" "cis" {
  count = var.enable_security_hub && var.enable_cis_standard ? 1 : 0

  depends_on    = [aws_securityhub_account.main]
  standards_arn = "arn:aws:securityhub:${var.region}::standards/cis-aws-foundations-benchmark/v/1.4.0"
}

# Enable AWS Foundational Security Best Practices
resource "aws_securityhub_standards_subscription" "fsbp" {
  count = var.enable_security_hub && var.enable_fsbp_standard ? 1 : 0

  depends_on    = [aws_securityhub_account.main]
  standards_arn = "arn:aws:securityhub:${var.region}::standards/aws-foundational-security-best-practices/v/1.0.0"
}

# Enable PCI-DSS Standard
resource "aws_securityhub_standards_subscription" "pci_dss" {
  count = var.enable_security_hub && var.enable_pci_standard ? 1 : 0

  depends_on    = [aws_securityhub_account.main]
  standards_arn = "arn:aws:securityhub:${var.region}::standards/pci-dss/v/3.2.1"
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

  tags = merge(
    var.tags,
    {
      Name = "${local.name_prefix}-alerts"
    }
  )
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
  count = var.enable_guardduty ? 1 : 0

  name        = "${local.name_prefix}-guardduty-findings"
  description = "Capture GuardDuty HIGH and CRITICAL findings"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail = {
      severity = [4, 4.0, 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7, 4.8, 4.9, 5, 5.0, 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 5.7, 5.8, 5.9, 6, 6.0, 6.1, 6.2, 6.3, 6.4, 6.5, 6.6, 6.7, 6.8, 6.9, 7, 7.0, 7.1, 7.2, 7.3, 7.4, 7.5, 7.6, 7.7, 7.8, 7.9, 8, 8.0, 8.1, 8.2, 8.3, 8.4, 8.5, 8.6, 8.7, 8.8, 8.9]
    }
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "guardduty_sns" {
  count = var.enable_guardduty ? 1 : 0

  rule      = aws_cloudwatch_event_rule.guardduty_findings[0].name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.security_alerts.arn
}

# EventBridge rule for Security Hub findings
resource "aws_cloudwatch_event_rule" "securityhub_findings" {
  count = var.enable_security_hub ? 1 : 0

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

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "securityhub_sns" {
  count = var.enable_security_hub ? 1 : 0

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

  tags = var.tags
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

  filename         = "${path.module}/lambda/alert-enrichment.zip"
  function_name    = "${local.name_prefix}-alert-enrichment"
  role             = aws_iam_role.alert_enrichment[0].arn
  handler          = "index.handler"
  source_code_hash = filebase64sha256("${path.module}/lambda/alert-enrichment.zip")
  runtime          = "python3.11"
  timeout          = 60
  memory_size      = 256

  environment {
    variables = {
      SLACK_WEBHOOK_URL  = var.slack_webhook_url != null ? var.slack_webhook_url : ""
      PAGERDUTY_API_KEY  = var.pagerduty_integration_key != null ? var.pagerduty_integration_key : ""
      ENVIRONMENT        = var.tags["Environment"]
    }
  }

  tags = var.tags
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

  tags = var.tags
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

  tags = var.tags
}

# CloudWatch alarms for security events
resource "aws_cloudwatch_metric_alarm" "guardduty_high_findings" {
  count = var.enable_guardduty ? 1 : 0

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

  tags = var.tags
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

  tags = var.tags
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

  tags = var.tags
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

  tags = var.tags
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

  tags = var.tags
}

# Data source for current AWS account
data "aws_caller_identity" "current" {}
