locals {
  name_prefix = "${var.tags["Environment"]}-${lookup(var.tags, "Name", "security")}"

  # The detector, the hub and the Inspector enabler are owned by the
  # guardduty, securityhub and inspector2 components (one component per
  # service, the Cloud Posse model). This component only routes their
  # findings, so a null ID turns the matching EventBridge rule off -- unless
  # require_*_route is set, in which case the topic's precondition fails the
  # plan instead. Inspector is opt-in (inspector2 enabled defaults to false and
  # returns a null account_id), so its route has no require_* switch. The CloudTrail log group
  # works the same way for the CIS metric filters and alarms. All are plain
  # variables, so the counts below are known at plan time.
  guardduty_enabled    = var.guardduty_detector_id != null
  security_hub_enabled = var.securityhub_account_arn != null
  inspector_enabled    = var.inspector2_account_id != null
  cloudtrail_enabled   = var.cloudtrail_log_group_name != null

  # CIS AWS Foundations Benchmark v1.2.0 metric filters (the version Security
  # Hub's default CIS standard checks, controls CloudWatch.1/.2/.4/.10), on the
  # log group the cloudtrail component's trail delivers to. Metric names are
  # the CloudTrailMetrics names the alarms below watch.
  cloudtrail_metric_filters = {
    root_account_usage = {
      metric  = "RootAccountUsage"
      pattern = "{$.userIdentity.type=\"Root\" && $.userIdentity.invokedBy NOT EXISTS && $.eventType !=\"AwsServiceEvent\"}"
    }
    unauthorized_api_calls = {
      metric  = "UnauthorizedAPICalls"
      pattern = "{($.errorCode=\"*UnauthorizedOperation\") || ($.errorCode=\"AccessDenied*\")}"
    }
    iam_policy_changes = {
      metric  = "IAMPolicyChanges"
      pattern = "{($.eventName=DeleteGroupPolicy)||($.eventName=DeleteRolePolicy)||($.eventName=DeleteUserPolicy)||($.eventName=PutGroupPolicy)||($.eventName=PutRolePolicy)||($.eventName=PutUserPolicy)||($.eventName=CreatePolicy)||($.eventName=DeletePolicy)||($.eventName=CreatePolicyVersion)||($.eventName=DeletePolicyVersion)||($.eventName=AttachRolePolicy)||($.eventName=DetachRolePolicy)||($.eventName=AttachUserPolicy)||($.eventName=DetachUserPolicy)||($.eventName=AttachGroupPolicy)||($.eventName=DetachGroupPolicy)}"
    }
    security_group_changes = {
      metric  = "SecurityGroupChanges"
      pattern = "{($.eventName=AuthorizeSecurityGroupIngress) || ($.eventName=AuthorizeSecurityGroupEgress) || ($.eventName=RevokeSecurityGroupIngress) || ($.eventName=RevokeSecurityGroupEgress) || ($.eventName=CreateSecurityGroup) || ($.eventName=DeleteSecurityGroup)}"
    }
  }

  # EC2 API calls that create, delete or change a security group or its rules
  # (the security_group_changes EventBridge rule).
  security_group_change_events = [
    "AuthorizeSecurityGroupIngress",
    "AuthorizeSecurityGroupEgress",
    "RevokeSecurityGroupIngress",
    "RevokeSecurityGroupEgress",
    "CreateSecurityGroup",
    "DeleteSecurityGroup",
    "ModifySecurityGroupRules",
  ]

  # Automation roles whose security group changes are not alerted. Nulls are
  # dropped: iam/ci returns a null ci_apply_role_arn while its apply role is
  # disabled.
  security_group_change_excluded_role_arns = distinct(compact(var.security_group_change_excluded_role_arns))

  # Who made the call, for the security_group_changes rule. EventBridge
  # matches a field-level condition only when the field is present, and
  # anything-but is no exception: {"anything-but": [...]} on
  # sessionIssuer.arn does NOT match an event that has no sessionIssuer. Only
  # assumed-role sessions carry one; root, IAM users and AWS service events
  # (userIdentity.type Root, IAMUser, AWSService) do not. So the anything-but
  # alone would drop exactly the human and root changes this rule exists for.
  # The $or keeps them: the first branch matches assumed-role calls by any
  # role not listed, the second matches every call without a sessionIssuer
  # ({"exists": false} on the leaf also holds when sessionContext itself is
  # absent). Two branches, two rule combinations (limit 1000). With no
  # excluded roles the condition is left out entirely: an empty anything-but
  # list is not a valid pattern.
  security_group_change_principal_filter = length(local.security_group_change_excluded_role_arns) == 0 ? null : {
    "$or" = [
      { userIdentity = { sessionContext = { sessionIssuer = { arn = [{ anything-but = local.security_group_change_excluded_role_arns }] } } } },
      { userIdentity = { sessionContext = { sessionIssuer = { arn = [{ exists = false }] } } } },
    ]
  }

  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
}

# SNS Topic for Security Alerts
resource "aws_sns_topic" "security_alerts" {
  name              = "${local.name_prefix}-alerts"
  display_name      = "Security Alerts for ${var.tags["Environment"]}"
  kms_master_key_id = var.kms_key_id

  tags = { Name = "${local.name_prefix}-alerts" }

  # A null ID silently turns a finding route off. On a first deploy that means
  # guardduty/securityhub had no state yet; failing here makes that loud.
  lifecycle {
    precondition {
      condition     = !var.require_guardduty_route || local.guardduty_enabled
      error_message = "require_guardduty_route is set but guardduty_detector_id is null. Apply guardduty/main first (its detector_id output), or set require_guardduty_route = false to run without GuardDuty alerting."
    }

    precondition {
      condition     = !var.require_securityhub_route || local.security_hub_enabled
      error_message = "require_securityhub_route is set but securityhub_account_arn is null. Apply securityhub/main first (its account_arn output), or set require_securityhub_route = false to run without Security Hub alerting."
    }

    precondition {
      condition     = !var.require_cloudtrail_route || local.cloudtrail_enabled
      error_message = "require_cloudtrail_route is set but cloudtrail_log_group_name is null. Apply cloudtrail/main first (its cloudtrail_logs_log_group_name output), or set require_cloudtrail_route = false to run without the CIS CloudTrail alarms."
    }
  }
}

resource "aws_sns_topic_policy" "security_alerts" {
  arn = aws_sns_topic.security_alerts.arn

  # Same-account publishers only: aws:SourceAccount stops another account's
  # rule or alarm from using this topic (confused deputy), and aws:SourceArn
  # narrows each service to its own resource type in this region.
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
        Condition = {
          StringEquals = { "aws:SourceAccount" = local.account_id }
          ArnLike      = { "aws:SourceArn" = "arn:${local.partition}:events:${var.region}:${local.account_id}:rule/*" }
        }
      },
      {
        Sid    = "AllowCloudWatchToPublish"
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.security_alerts.arn
        Condition = {
          StringEquals = { "aws:SourceAccount" = local.account_id }
          ArnLike      = { "aws:SourceArn" = "arn:${local.partition}:cloudwatch:${var.region}:${local.account_id}:alarm:*" }
        }
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
  description = "Capture new, active, failed Security Hub HIGH and CRITICAL findings"

  # Security Hub re-imports a finding on every update. RecordState ACTIVE drops
  # archived findings and Workflow.Status NEW drops those already triaged
  # (NOTIFIED, SUPPRESSED, RESOLVED). A finding still in NEW matches again on
  # each re-import, so it can alert more than once until someone triages it.
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
        RecordState = ["ACTIVE"]
        Workflow = {
          Status = ["NEW"]
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

# EventBridge rule for Inspector findings (inspector2 component)
resource "aws_cloudwatch_event_rule" "inspector_findings" {
  count = local.inspector_enabled ? 1 : 0

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
  count = local.inspector_enabled ? 1 : 0

  rule      = aws_cloudwatch_event_rule.inspector_findings[0].name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.security_alerts.arn
}

# Security group changes, one event per change. This is an account-and-region
# concern, so it lives here and not in the securitygroup component (which runs
# once per group set and used to create a target-less copy of this rule per
# instance). It complements the CIS SecurityGroupChanges alarm below: the
# alarm counts changes in the trail's log group against sg_changes_threshold,
# this rule delivers each change (who, which group, which API call) as it
# happens, including ModifySecurityGroupRules, which the CIS pattern omits.
# EventBridge receives these "AWS API Call via CloudTrail" events from the
# account trail (cloudtrail/main). Calls made by the roles in
# security_group_change_excluded_role_arns (controllers, EKS, CI applies) are
# left to the alarm; see security_group_change_principal_filter above.
# UpdateSecurityGroupRuleDescriptions* is not matched: it changes a rule's
# description only, never what the group allows.
resource "aws_cloudwatch_event_rule" "security_group_changes" {
  count = var.enable_security_group_change_events ? 1 : 0

  name        = "${local.name_prefix}-security-group-changes"
  description = "Capture security group create, delete and rule changes not made by automation roles"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = merge({
      eventSource = ["ec2.amazonaws.com"]
      eventName   = local.security_group_change_events
    }, local.security_group_change_principal_filter)
  })
}

resource "aws_cloudwatch_event_target" "security_group_changes_sns" {
  count = var.enable_security_group_change_events ? 1 : 0

  rule      = aws_cloudwatch_event_rule.security_group_changes[0].name
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

# CIS metric filters feeding the CloudTrailMetrics alarms below. Without them
# the alarms watch metrics nothing publishes.
resource "aws_cloudwatch_log_metric_filter" "cloudtrail" {
  for_each = local.cloudtrail_enabled ? local.cloudtrail_metric_filters : {}

  name           = "${local.name_prefix}-${replace(each.key, "_", "-")}"
  log_group_name = var.cloudtrail_log_group_name
  pattern        = each.value.pattern

  metric_transformation {
    name      = each.value.metric
    namespace = "CloudTrailMetrics"
    value     = "1"
  }
}

# Root account usage alarm
resource "aws_cloudwatch_metric_alarm" "root_account_usage" {
  count = local.cloudtrail_enabled ? 1 : 0

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

  depends_on = [aws_cloudwatch_log_metric_filter.cloudtrail]
}

# Unauthorized API calls alarm
resource "aws_cloudwatch_metric_alarm" "unauthorized_api_calls" {
  count = local.cloudtrail_enabled ? 1 : 0

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

  depends_on = [aws_cloudwatch_log_metric_filter.cloudtrail]
}

# IAM policy changes alarm
resource "aws_cloudwatch_metric_alarm" "iam_policy_changes" {
  count = local.cloudtrail_enabled ? 1 : 0

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

  depends_on = [aws_cloudwatch_log_metric_filter.cloudtrail]
}

# Security group changes alarm
resource "aws_cloudwatch_metric_alarm" "security_group_changes" {
  count = local.cloudtrail_enabled ? 1 : 0

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

  depends_on = [aws_cloudwatch_log_metric_filter.cloudtrail]
}

# Data source for current AWS account
data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}
