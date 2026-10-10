# EventBridge relay of the failover health check's alarm
# (health_check_alarm_relay_regions).
#
# Route 53 publishes HealthCheckStatus in us-east-1 only, so the alarm
# (main.tf) is there. A US stack notifies its monitoring topic in us-east-1
# (health_check_alarm_actions). An EU stack must not keep anything persistent
# in us-east-1 (owner decision B5: no topic, key or staff email addresses
# there), so its alarm has no action: a us-east-1 EventBridge rule matches this
# alarm's own "CloudWatch Alarm State Change" events and forwards them to the
# default event bus of each listed region, where the monitoring component
# (receive_relayed_health_check_alarms) delivers them to that region's alarm
# topic. Relaying to both EU regions keeps the PRIMARY's alarm deliverable
# while its own region is down, which is when it matters.
#
# In us-east-1 this creates only configuration: the rule, one target per
# region and the IAM role (global) the targets use. No archive, dead-letter
# queue, topic or key: no event is stored there. Events carry the alarm's
# name, state and reason (health check metadata), no personal data.
#
# Shape: Cloud Posse terraform-aws-cloudwatch-events (aws_cloudwatch_event_rule
# + aws_cloudwatch_event_target); the cross-region event-bus target with a role
# follows AWS's "Sending events between event buses in different Regions".

locals {
  health_check_alarm_region = "us-east-1"
  relay_health_check_alarm  = length(var.health_check_alarm_relay_regions) > 0 && length(aws_route53_health_check.api) > 0
  relay_name                = "${local.name_prefix}-health-check-relay"

  # Every region's default bus exists without being created: its ARN is built,
  # not read (the monitoring component that receives there deploys after this
  # one and reads it, so a read back would be a cycle).
  relay_event_bus_arns = {
    for r in var.health_check_alarm_relay_regions :
    r => "arn:${data.aws_partition.current.partition}:events:${r}:${data.aws_caller_identity.current.account_id}:event-bus/default"
  }
}

data "aws_partition" "current" {}

data "aws_caller_identity" "current" {}

resource "aws_cloudwatch_event_rule" "health_check_relay" {
  count  = local.relay_health_check_alarm ? 1 : 0
  region = local.health_check_alarm_region

  name        = local.relay_name
  description = "Relays ${aws_cloudwatch_metric_alarm.health_check[0].alarm_name} state changes to ${join(", ", var.health_check_alarm_relay_regions)}"

  # This component's own alarm only, by its exact ARN.
  event_pattern = jsonencode({
    source        = ["aws.cloudwatch"]
    "detail-type" = ["CloudWatch Alarm State Change"]
    resources     = [aws_cloudwatch_metric_alarm.health_check[0].arn]
  })

  tags = merge(local.tags, { Name = local.relay_name })
}

resource "aws_iam_role" "health_check_relay" {
  count = local.relay_health_check_alarm ? 1 : 0

  name = local.relay_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          "aws:SourceArn"     = aws_cloudwatch_event_rule.health_check_relay[0].arn
        }
      }
    }]
  })

  tags = merge(local.tags, { Name = local.relay_name })
}

# PutEvents on the target buses only.
resource "aws_iam_role_policy" "health_check_relay" {
  count = local.relay_health_check_alarm ? 1 : 0

  name = "put-events"
  role = aws_iam_role.health_check_relay[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "PutEventsOnTheRelayBuses"
      Effect   = "Allow"
      Action   = "events:PutEvents"
      Resource = [for r in var.health_check_alarm_relay_regions : local.relay_event_bus_arns[r]]
    }]
  })
}

resource "aws_cloudwatch_event_target" "health_check_relay" {
  for_each = local.relay_health_check_alarm ? toset(var.health_check_alarm_relay_regions) : toset([])
  region   = local.health_check_alarm_region

  rule      = aws_cloudwatch_event_rule.health_check_relay[0].name
  target_id = "relay-${each.key}"
  arn       = local.relay_event_bus_arns[each.key]
  role_arn  = aws_iam_role.health_check_relay[0].arn
}
