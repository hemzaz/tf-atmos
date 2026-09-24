# security-monitoring consumes GuardDuty and Security Hub; it never creates them.
#
# The guardduty and securityhub components own the detector and the hub (one
# component per service, the Cloud Posse model). Stacks pass their IDs in with
# !terraform.state. These runs prove that the finding routes follow those IDs,
# that a null ID fails the plan unless the route is explicitly optional, that a
# null ID turns an optional route off, and that malformed IDs are rejected.
#
# mock_provider avoids needing real AWS credentials. Most runs use
# `command = plan`; the topic-policy run applies against the mock so the topic
# ARN inside the policy is known.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_resource "aws_sns_topic" {
    defaults = {
      arn = "arn:aws:sns:eu-west-2:123456789012:test-security-alerts"
    }
  }
}

variables {
  region = "eu-west-2"
  tags = {
    Environment = "test"
    Tenant      = "fnx"
    ManagedBy   = "Terraform"
  }
  enable_inspector        = false
  guardduty_detector_id   = "12abc34d567e8fa901bc2d34e56789f0"
  securityhub_account_arn = "arn:aws:securityhub:eu-west-2:123456789012:hub/default"
  kms_key_id              = "arn:aws:kms:eu-west-2:123456789012:key/12345678-1234-1234-1234-123456789012"
}

run "routes_consumed_detector_and_hub" {
  command = plan

  assert {
    condition     = length(aws_cloudwatch_event_rule.guardduty_findings) == 1 && length(aws_cloudwatch_event_rule.securityhub_findings) == 1
    error_message = "Both finding routes must exist when the detector ID and hub ARN are passed in."
  }

  assert {
    condition     = jsondecode(aws_cloudwatch_event_rule.guardduty_findings[0].event_pattern).detail.severity[0].numeric == [">=", 4]
    error_message = "GuardDuty findings must be routed from severity 4.0 up, CRITICAL (9.0-10.0) included."
  }

  assert {
    condition     = jsondecode(aws_cloudwatch_event_rule.securityhub_findings[0].event_pattern).detail.findings.RecordState == ["ACTIVE"]
    error_message = "Security Hub findings must be filtered to RecordState ACTIVE (archived findings dropped)."
  }

  assert {
    condition     = jsondecode(aws_cloudwatch_event_rule.securityhub_findings[0].event_pattern).detail.findings.Workflow.Status == ["NEW"]
    error_message = "Security Hub findings must be filtered to Workflow.Status NEW (triaged findings dropped)."
  }

  assert {
    condition     = aws_sns_topic.security_alerts.kms_master_key_id == var.kms_key_id
    error_message = "The alert topic must be encrypted with the key passed in (kms/main)."
  }

  assert {
    condition     = output.guardduty_detector_id == "12abc34d567e8fa901bc2d34e56789f0"
    error_message = "guardduty_detector_id must pass the consumed detector ID through."
  }

  assert {
    condition     = output.security_hub_account_arn == "arn:aws:securityhub:eu-west-2:123456789012:hub/default"
    error_message = "security_hub_account_arn must pass the consumed hub ARN through."
  }
}

run "topic_policy_is_same_account_only" {
  command = apply

  assert {
    condition = alltrue([
      for s in jsondecode(aws_sns_topic_policy.security_alerts.policy).Statement :
      s.Condition.StringEquals["aws:SourceAccount"] == "123456789012"
    ])
    error_message = "Every publish statement must be limited to this account (aws:SourceAccount)."
  }

  assert {
    condition = one([
      for s in jsondecode(aws_sns_topic_policy.security_alerts.policy).Statement :
      s.Condition.ArnLike["aws:SourceArn"] if s.Principal.Service == "events.amazonaws.com"
    ]) == "arn:aws:events:eu-west-2:123456789012:rule/*"
    error_message = "EventBridge may publish only from this account's rules in this region."
  }

  assert {
    condition = one([
      for s in jsondecode(aws_sns_topic_policy.security_alerts.policy).Statement :
      s.Condition.ArnLike["aws:SourceArn"] if s.Principal.Service == "cloudwatch.amazonaws.com"
    ]) == "arn:aws:cloudwatch:eu-west-2:123456789012:alarm:*"
    error_message = "CloudWatch may publish only from this account's alarms in this region."
  }
}

run "null_detector_fails_when_route_required" {
  command = plan

  variables {
    guardduty_detector_id = null
  }

  expect_failures = [aws_sns_topic.security_alerts]
}

run "null_hub_fails_when_route_required" {
  command = plan

  variables {
    securityhub_account_arn = null
  }

  expect_failures = [aws_sns_topic.security_alerts]
}

run "null_ids_disable_optional_routes" {
  command = plan

  variables {
    guardduty_detector_id     = null
    securityhub_account_arn   = null
    require_guardduty_route   = false
    require_securityhub_route = false
  }

  assert {
    condition     = length(aws_cloudwatch_event_rule.guardduty_findings) == 0
    error_message = "Without a detector ID there must be no GuardDuty route."
  }

  assert {
    condition     = length(aws_cloudwatch_event_rule.securityhub_findings) == 0
    error_message = "Without a hub ARN there must be no Security Hub route."
  }

  assert {
    condition     = output.guardduty_detector_id == null && output.security_hub_account_arn == null
    error_message = "Both pass-through outputs must be null when nothing is consumed."
  }
}

run "rejects_malformed_detector_id" {
  command = plan

  variables {
    guardduty_detector_id = "arn:aws:guardduty:eu-west-2:123456789012:detector/abc"
  }

  expect_failures = [var.guardduty_detector_id]
}

run "rejects_non_hub_arn" {
  command = plan

  variables {
    securityhub_account_arn = "123456789012"
  }

  expect_failures = [var.securityhub_account_arn]
}

run "rejects_non_arn_kms_key" {
  command = plan

  variables {
    kms_key_id = "alias/main"
  }

  expect_failures = [var.kms_key_id]
}
