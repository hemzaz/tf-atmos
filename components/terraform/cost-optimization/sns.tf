# ========================================
# SNS Topic for Cost Alerts
# ========================================
# Encrypted with kms/main (var.kms_key_arn). Two kinds of publisher need key
# access: the publishing Lambda roles (savings_analyzer, resource_cleanup)
# get their own kms:GenerateDataKey*/kms:Decrypt grant scoped to this
# topic's encryption context - see iam.tf - and the three *_errors alarms
# publish here as cloudwatch.amazonaws.com, which relies on kms/main's
# allow_cloudwatch_alarms flag (catalog/kms/defaults.yaml). With
# billing_notifications_sns_enabled, the budget and the anomaly subscription
# publish here too, as budgets.amazonaws.com and costalerts.amazonaws.com,
# which relies on kms/main's allow_billing_notifications.

resource "aws_sns_topic" "cost_alerts" {
  name              = "${local.name}-cost-alerts"
  kms_master_key_id = var.kms_key_arn

  tags = { Name = "${local.name}-cost-alerts" }
}

resource "aws_sns_topic_subscription" "cost_alerts_email" {
  for_each = toset(var.cost_alert_emails)

  topic_arn = aws_sns_topic.cost_alerts.arn
  protocol  = "email"
  endpoint  = each.value
}

# The topic's policy, set only with billing_notifications_sns_enabled
# (otherwise the topic keeps SNS's default policy). It keeps the *_errors
# alarms' access (this account's CloudWatch alarms in this region, as
# monitoring's topic) and lets the budget and the anomaly subscription publish.
# Conditions as AWS documents them (budgets-sns-policy, ad-SNS). The Lambda
# roles publish through their own IAM grants (iam.tf), which suffice within the
# account.
resource "aws_sns_topic_policy" "cost_alerts" {
  count = var.billing_notifications_sns_enabled ? 1 : 0

  arn = aws_sns_topic.cost_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudWatchAlarmsToPublish"
        Effect    = "Allow"
        Principal = { Service = "cloudwatch.amazonaws.com" }
        Action    = "SNS:Publish"
        Resource  = local.cost_alerts_topic_arn
        Condition = {
          StringEquals = { "aws:SourceAccount" = local.account_id }
          ArnLike      = { "aws:SourceArn" = "arn:aws:cloudwatch:${var.region}:${local.account_id}:alarm:*" }
        }
      },
      {
        Sid       = "AllowBudgetsToPublish"
        Effect    = "Allow"
        Principal = { Service = "budgets.amazonaws.com" }
        Action    = "SNS:Publish"
        Resource  = local.cost_alerts_topic_arn
        Condition = {
          StringEquals = { "aws:SourceAccount" = local.account_id }
          ArnLike      = { "aws:SourceArn" = "arn:aws:budgets::${local.account_id}:*" }
        }
      },
      {
        Sid       = "AllowCostAnomalyDetectionToPublish"
        Effect    = "Allow"
        Principal = { Service = "costalerts.amazonaws.com" }
        Action    = "SNS:Publish"
        Resource  = local.cost_alerts_topic_arn
        Condition = {
          StringEquals = { "aws:SourceAccount" = local.account_id }
        }
      },
    ]
  })
}
