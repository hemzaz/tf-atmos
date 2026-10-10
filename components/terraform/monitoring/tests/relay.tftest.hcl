# Mock-provider tests for the receiving end of the apigateway health check
# alarm relay (receive_relayed_health_check_alarms, owner decision B5): no AWS
# credentials, no network. Run from the component directory with
# `terraform init -backend=false && terraform test`.

mock_provider "aws" {}

variables {
  region           = "eu-central-1"
  name             = "main"
  create_sns_topic = true
  kms_key_id       = "arn:aws:kms:eu-central-1:123456789012:key/mrk-1234567890abcdef1234567890abcdef"
  tags = {
    Environment = "ec1"
    Tenant      = "fnx"
    ManagedBy   = "Terraform"
  }
}

run "relayed_health_check_alarms_reach_the_topic" {
  command = plan

  variables {
    receive_relayed_health_check_alarms = true
  }

  override_data {
    target = data.aws_caller_identity.current
    values = { account_id = "123456789012" }
  }

  override_data {
    target = data.aws_partition.current
    values = { partition = "aws" }
  }

  override_resource {
    target          = aws_sns_topic.alarms
    override_during = plan
    values          = { arn = "arn:aws:sns:eu-central-1:123456789012:ec1-main-alarms" }
  }

  override_resource {
    target          = aws_cloudwatch_event_rule.relayed_health_check_alarms
    override_during = plan
    values          = { arn = "arn:aws:events:eu-central-1:123456789012:rule/ec1-main-health-check-alarms" }
  }

  assert {
    condition = jsondecode(aws_cloudwatch_event_rule.relayed_health_check_alarms[0].event_pattern) == {
      source        = ["aws.cloudwatch"]
      "detail-type" = ["CloudWatch Alarm State Change"]
      account       = ["123456789012"]
      region        = ["us-east-1"]
      resources     = [{ wildcard = "arn:aws:cloudwatch:us-east-1:123456789012:alarm:*-health-check" }]
    }
    error_message = "The rule must match only this account's relayed us-east-1 health check alarms."
  }

  assert {
    condition     = aws_cloudwatch_event_rule.relayed_health_check_alarms[0].event_bus_name == "default" && aws_cloudwatch_event_target.relayed_health_check_alarms[0].arn == "arn:aws:sns:eu-central-1:123456789012:ec1-main-alarms"
    error_message = "The rule on this region's default bus must deliver to this component's topic."
  }

  assert {
    condition = (
      jsondecode(aws_sns_topic_policy.alarms[0].policy).Statement[1].Principal.Service == "events.amazonaws.com"
      && jsondecode(aws_sns_topic_policy.alarms[0].policy).Statement[1].Condition.ArnEquals["aws:SourceArn"] == "arn:aws:events:eu-central-1:123456789012:rule/ec1-main-health-check-alarms"
      && jsondecode(aws_sns_topic_policy.alarms[0].policy).Statement[1].Condition.StringEquals["aws:SourceAccount"] == "123456789012"
      && jsondecode(aws_sns_topic_policy.alarms[0].policy).Statement[0].Principal.Service == "cloudwatch.amazonaws.com"
    )
    error_message = "The topic policy must admit this region's CloudWatch alarms and the relay rule only."
  }
}

run "no_relay_receiver_by_default" {
  command = plan

  assert {
    condition     = length(aws_cloudwatch_event_rule.relayed_health_check_alarms) == 0 && length(aws_sns_topic_policy.alarms) == 0
    error_message = "Without receive_relayed_health_check_alarms no rule and the topic keeps its default policy."
  }
}

run "receiver_without_topic_is_rejected" {
  command = plan

  variables {
    receive_relayed_health_check_alarms = true
    create_sns_topic                    = false
  }

  expect_failures = [var.receive_relayed_health_check_alarms]
}
