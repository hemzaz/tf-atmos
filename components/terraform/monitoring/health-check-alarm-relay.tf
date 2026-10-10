# The receiving end of the apigateway health check alarm relay
# (receive_relayed_health_check_alarms; apigateway health-check-alarm-relay.tf).
#
# Route 53 health check alarms live in us-east-1. A stack that keeps nothing
# persistent there (an EU stack, owner decision B5) has its apigateway relay
# each alarm's "CloudWatch Alarm State Change" events to the default event bus
# of every region of the failover pair. This rule, on this region's default
# bus, delivers the relayed ones to this component's alarm topic, so the
# alarm's subscribers are reached from this region whichever region failed.
#
# The pattern matches the account's us-east-1 alarms named "*-health-check"
# (apigateway's "<Environment>-<api_name>-<primary|secondary>-health-check"):
# only a relay rule brings us-east-1 events to a bus in this region, and this
# matches both halves of the pair, including the peer stack's, whose state this
# stack cannot read (the peer deploys after it, or reads it).
#
# Shape: Cloud Posse terraform-aws-cloudwatch-events (rule + target). The
# topic's key must allow EventBridge to publish (kms allow_eventbridge).

locals {
  receive_relayed_alarms = var.receive_relayed_health_check_alarms && var.create_sns_topic
  relay_rule_name        = "${local.name_prefix}-health-check-alarms"
}

data "aws_partition" "current" {}

data "aws_caller_identity" "current" {}

resource "aws_cloudwatch_event_rule" "relayed_health_check_alarms" {
  count = local.receive_relayed_alarms ? 1 : 0

  name           = local.relay_rule_name
  event_bus_name = "default"
  description    = "Relayed us-east-1 Route 53 health check alarm state changes, to ${local.name_prefix}-alarms"

  event_pattern = jsonencode({
    source        = ["aws.cloudwatch"]
    "detail-type" = ["CloudWatch Alarm State Change"]
    account       = [data.aws_caller_identity.current.account_id]
    region        = ["us-east-1"]
    resources = [{
      wildcard = "arn:${data.aws_partition.current.partition}:cloudwatch:us-east-1:${data.aws_caller_identity.current.account_id}:alarm:*-health-check"
    }]
  })

  tags = { Name = local.relay_rule_name }
}

resource "aws_cloudwatch_event_target" "relayed_health_check_alarms" {
  count = local.receive_relayed_alarms ? 1 : 0

  rule           = aws_cloudwatch_event_rule.relayed_health_check_alarms[0].name
  event_bus_name = "default"
  target_id      = "alarm-topic"
  arn            = aws_sns_topic.alarms[0].arn
}

# The topic's policy, set only with the relay or allow_rds_event_publish
# (otherwise the topic keeps SNS's default policy, as before). It keeps what
# this component's alarms need, the same-account CloudWatch alarms of this
# region (as security-monitoring's topic), and adds the relay rule and/or this
# account's and region's RDS event subscriptions (rds sns_topic_arn ->
# aws_db_event_subscription).
locals {
  alarm_topic_policy_enabled = var.create_sns_topic && (local.receive_relayed_alarms || var.allow_rds_event_publish)

  alarm_topic_statements = local.alarm_topic_policy_enabled ? concat(
    [{
      Sid       = "AllowCloudWatchAlarmsToPublish"
      Effect    = "Allow"
      Principal = { Service = "cloudwatch.amazonaws.com" }
      Action    = "SNS:Publish"
      Resource  = aws_sns_topic.alarms[0].arn
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
        ArnLike      = { "aws:SourceArn" = "arn:${data.aws_partition.current.partition}:cloudwatch:${var.region}:${data.aws_caller_identity.current.account_id}:alarm:*" }
      }
    }],
    local.receive_relayed_alarms ? [{
      Sid       = "AllowTheRelayRuleToPublish"
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "SNS:Publish"
      Resource  = aws_sns_topic.alarms[0].arn
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
        ArnEquals    = { "aws:SourceArn" = aws_cloudwatch_event_rule.relayed_health_check_alarms[0].arn }
      }
    }] : [],
    var.allow_rds_event_publish ? [{
      Sid       = "AllowRdsEventSubscriptionsToPublish"
      Effect    = "Allow"
      Principal = { Service = "events.rds.amazonaws.com" }
      Action    = "SNS:Publish"
      Resource  = aws_sns_topic.alarms[0].arn
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
        ArnLike      = { "aws:SourceArn" = "arn:${data.aws_partition.current.partition}:rds:${var.region}:${data.aws_caller_identity.current.account_id}:es:*" }
      }
    }] : [],
  ) : []
}

resource "aws_sns_topic_policy" "alarms" {
  count = local.alarm_topic_policy_enabled ? 1 : 0

  arn = aws_sns_topic.alarms[0].arn

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = local.alarm_topic_statements
  })
}
