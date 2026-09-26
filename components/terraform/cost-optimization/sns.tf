# ========================================
# SNS Topic for Cost Alerts
# ========================================
# Encrypted with kms/main (var.kms_key_arn). Two kinds of publisher need key
# access: the publishing Lambda roles (savings_analyzer, resource_cleanup)
# get their own kms:GenerateDataKey*/kms:Decrypt grant scoped to this
# topic's encryption context - see iam.tf - and the three *_errors alarms
# publish here as cloudwatch.amazonaws.com, which relies on kms/main's
# allow_cloudwatch_alarms flag (catalog/kms/defaults.yaml).

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
