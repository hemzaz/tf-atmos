# The failover health check's own alarm topic (create_health_check_alarm_topic).
#
# Route 53 publishes HealthCheckStatus in us-east-1 only, so the alarm
# (main.tf) and every topic it notifies are there. A US stack names its
# monitoring topic in us-east-1 (health_check_alarm_actions); an EU stack has
# none there and must not have a non-EU stack read its state, so this
# component creates the topic itself, in us-east-1 through the resource-level
# `region` argument (AWS provider v6, as the alarm and dns/query-logging.tf),
# with its own us-east-1 key: the EU key (kms/main) has no us-east-1 replica
# and must not get one. It carries alarm state changes only (health check id,
# domain name), no personal data (owner decision B5;
# check-data-residency.py EXEMPTIONS).
#
# Cloud Posse's aws-api-gateway-rest-api has no failover or health check; the
# topic, key and policy follow monitoring's alarm topic, the kms component's
# CloudWatch alarm statement and security-monitoring's topic policy.

locals {
  health_check_alarm_region = "us-east-1"
  health_check_alarm_topic  = "${local.name_prefix}-health-check-alarms"

  create_health_check_alarm_topic = var.create_health_check_alarm_topic && length(aws_route53_health_check.api) > 0
}

data "aws_partition" "current" {}

data "aws_caller_identity" "current" {}

resource "aws_kms_key" "health_check_alarms" {
  count  = local.create_health_check_alarm_topic ? 1 : 0
  region = local.health_check_alarm_region

  description             = "SNS topic ${local.health_check_alarm_topic} (Route 53 health check alarms, ${local.health_check_alarm_region})"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  # A key policy cannot reference its own ARN; "*" means "this key".
  # CloudWatch alarms of this account publishing to this account's topics in
  # us-east-1 (the kms component's AllowCloudWatchAlarmsSNSTopics).
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableAccountAdministration"
        Effect    = "Allow"
        Principal = { AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowCloudWatchAlarmsSNSTopics"
        Effect    = "Allow"
        Principal = { Service = "cloudwatch.amazonaws.com" }
        Action    = ["kms:GenerateDataKey*", "kms:Decrypt"]
        Resource  = "*"
        Condition = {
          StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
          ArnLike = {
            "kms:EncryptionContext:aws:sns:topicArn" = "arn:${data.aws_partition.current.partition}:sns:${local.health_check_alarm_region}:${data.aws_caller_identity.current.account_id}:*"
          }
        }
      },
    ]
  })

  tags = merge(local.tags, { Name = local.health_check_alarm_topic })
}

resource "aws_kms_alias" "health_check_alarms" {
  count  = local.create_health_check_alarm_topic ? 1 : 0
  region = local.health_check_alarm_region

  name          = "alias/${local.health_check_alarm_topic}"
  target_key_id = aws_kms_key.health_check_alarms[0].key_id
}

resource "aws_sns_topic" "health_check_alarms" {
  count  = local.create_health_check_alarm_topic ? 1 : 0
  region = local.health_check_alarm_region

  name              = local.health_check_alarm_topic
  kms_master_key_id = aws_kms_key.health_check_alarms[0].arn

  tags = merge(local.tags, { Name = local.health_check_alarm_topic })
}

# Same-account CloudWatch alarms in us-east-1 only (aws:SourceAccount against
# the confused deputy, aws:SourceArn to alarms), as security-monitoring's
# topic: this stack's alarm, and a DR stack's in this account that names the
# topic in its health_check_alarm_actions.
resource "aws_sns_topic_policy" "health_check_alarms" {
  count  = local.create_health_check_alarm_topic ? 1 : 0
  region = local.health_check_alarm_region

  arn = aws_sns_topic.health_check_alarms[0].arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudWatchAlarmsToPublish"
        Effect    = "Allow"
        Principal = { Service = "cloudwatch.amazonaws.com" }
        Action    = "SNS:Publish"
        Resource  = aws_sns_topic.health_check_alarms[0].arn
        Condition = {
          StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
          ArnLike      = { "aws:SourceArn" = "arn:${data.aws_partition.current.partition}:cloudwatch:${local.health_check_alarm_region}:${data.aws_caller_identity.current.account_id}:alarm:*" }
        }
      },
    ]
  })
}

resource "aws_sns_topic_subscription" "health_check_alarms_email" {
  for_each = local.create_health_check_alarm_topic ? toset(var.health_check_alarm_email_subscriptions) : toset([])
  region   = local.health_check_alarm_region

  topic_arn = aws_sns_topic.health_check_alarms[0].arn
  protocol  = "email"
  endpoint  = each.value
}
