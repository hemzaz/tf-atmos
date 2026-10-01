# API Gateway account settings for one account/region: the CloudWatch Logs role
# REST execution and access logging need, set on aws_api_gateway_account.
# Modelled on Cloud Posse aws-api-gateway-account-settings
# (cloudposse/api-gateway/aws//modules/account-settings). Deviation: Cloud Posse
# grants an inline logs:* policy on "*"; this role attaches the AWS managed
# AmazonAPIGatewayPushToCloudWatchLogs policy, which is what the AWS guide
# names and is maintained by AWS.
# https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-logging.html

locals {
  # IAM is global but the account setting is per region, so the region is in
  # the name: a second region's instance gets its own role, not a collision.
  role_name = "${var.tags["Environment"]}-apigateway-cloudwatch-${var.region}"
  partition = data.aws_partition.current.partition
}

data "aws_partition" "current" {}

# No aws:SourceAccount/aws:SourceArn condition: neither the AWS guide nor Cloud
# Posse sets one for this role, and API Gateway does not document passing those
# keys when it assumes the account's CloudWatch role, so a condition risks
# breaking every stage's logging.
data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  count = var.enabled ? 1 : 0

  name               = local.role_name
  description        = "Allows API Gateway to push execution and access logs to CloudWatch Logs"
  assume_role_policy = data.aws_iam_policy_document.assume.json

  tags = { Name = local.role_name }
}

resource "aws_iam_role_policy_attachment" "cloudwatch" {
  count = var.enabled ? 1 : 0

  role       = aws_iam_role.this[0].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

# Per-account, per-region singleton. reset_on_delete stays at the provider
# default, so destroying this only drops it from state; the account keeps the
# role ARN (and loses logging only if the role itself is gone).
resource "aws_api_gateway_account" "this" {
  count = var.enabled ? 1 : 0

  cloudwatch_role_arn = aws_iam_role.this[0].arn

  # API Gateway validates that it can assume the role when the setting is
  # written; the attachment must exist first.
  depends_on = [aws_iam_role_policy_attachment.cloudwatch]
}
