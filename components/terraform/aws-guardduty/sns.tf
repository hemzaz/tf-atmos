module "sns_topic" {
  source  = "cloudposse/sns-topic/aws"
  version = "1.2.0"
  count   = local.create_sns_topic ? 1 : 0

  subscribers        = local.sqs_subscribe
  sqs_dlq_enabled    = false
  encryption_enabled = true
  kms_master_key_id  = module.kms_key[0].key_id

  attributes = concat(module.this.attributes, ["guardduty"])
  context    = module.this.context
}

data "aws_iam_policy_document" "sns_topic_combined_policy" {
  count     = local.create_sns_topic ? 1 : 0
  policy_id = "GuardDutyPublishToSNS"

  # CloudWatch statement
  statement {
    sid = "AllowCloudWatchToPublish"
    actions = [
      "sns:Publish"
    ]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
    resources = [module.sns_topic[0].sns_topic.arn]
    effect    = "Allow"
  }

  # EventBridge statement
  statement {
    sid = "AllowEventsToPublish"
    actions = [
      "sns:Publish"
    ]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
    resources = [module.sns_topic[0].sns_topic.arn]
    effect    = "Allow"
  }

  statement {
    sid = "AllowSQSToSubscribe"
    actions = [
      "sns:Subscribe",
      "sns:Receive"
    ]
    principals {
      type        = "Service"
      identifiers = ["sqs.amazonaws.com"]
    }
    resources = [module.sns_topic[0].sns_topic.arn]
    effect    = "Allow"
  }
}

# Single policy resource
resource "aws_sns_topic_policy" "sns_topic_policy" {
  count  = module.this.enabled && local.create_sns_topic ? 1 : 0
  arn    = local.findings_notification_arn
  policy = data.aws_iam_policy_document.sns_topic_combined_policy[0].json
}

module "findings_label" {
  source  = "cloudposse/label/null"
  version = "0.25.0"

  attributes = concat(module.this.attributes, ["guardduty", "findings"])
  context    = module.this.context
}

resource "aws_cloudwatch_event_rule" "findings" {
  count       = local.enable_cloudwatch == true ? 1 : 0
  name        = module.findings_label.id
  description = "GuardDuty Findings"
  tags        = module.this.tags

  event_pattern = jsonencode(
    {
      "source" : [
        "aws.guardduty"
      ],
      "detail-type" : [
        var.cloudwatch_event_rule_pattern_detail_type
      ]
    }
  )
}

resource "aws_cloudwatch_event_target" "imported_findings" {
  count = local.enable_notifications == true ? 1 : 0
  rule  = aws_cloudwatch_event_rule.findings[0].name
  arn   = local.findings_notification_arn
}
