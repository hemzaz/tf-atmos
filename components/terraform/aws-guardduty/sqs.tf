# SQS queue for GuardDuty findings
# This queue is subscribed to the SNS topic to receive GuardDuty findings
module "sqs" {
  count   = local.sqs_enabled ? 1 : 0
  source  = "terraform-aws-modules/sqs/aws"
  version = "4.3.1"

  name                    = "${module.this.id}-guardduty-sqs"
  sqs_managed_sse_enabled = true
  tags                    = module.this.tags
}

module "queue_policy" {
  count   = local.sqs_enabled ? 1 : 0
  source  = "cloudposse/iam-policy/aws"
  version = "2.0.2"

  iam_policy = [
    {
      version = "2012-10-17"
      id      = "AllowSNSToSendToSQS"
      statements = [
        {
          sid    = "AllowSNSToSendToSQS"
          effect = "Allow"
          principals = [
            {
              type        = "Service"
              identifiers = ["sns.amazonaws.com"]
            }
          ]
          actions   = ["sqs:SendMessage"]
          resources = [module.sqs[0].queue_arn]
          conditions = [
            {
              test     = "ArnEquals"
              variable = "aws:SourceArn"
              values   = [module.sns_topic[0].sns_topic.arn]
            }
          ]
        }
      ]
    }
  ]

  context = module.this.context
}

resource "aws_sqs_queue_policy" "sqs_queue_policy" {
  count = local.sqs_enabled ? 1 : 0

  queue_url = module.sqs[0].queue_url
  policy    = one(module.queue_policy[*].json)
}
