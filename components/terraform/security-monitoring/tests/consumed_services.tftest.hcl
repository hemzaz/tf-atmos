# security-monitoring consumes GuardDuty and Security Hub; it never creates them.
#
# The guardduty and securityhub components own the detector and the hub (one
# component per service, the Cloud Posse model). Stacks pass their IDs in with
# !terraform.state. These runs prove that the finding routes follow those IDs,
# that a null ID turns a route off, and that malformed IDs are rejected.
#
# mock_provider avoids needing real AWS credentials. `command = plan` is
# enough because every assertion is knowable without calling AWS.

mock_provider "aws" {}

variables {
  region = "eu-west-2"
  tags = {
    Environment = "test"
    Tenant      = "fnx"
    ManagedBy   = "Terraform"
  }
  enable_inspector = false
}

run "routes_consumed_detector_and_hub" {
  command = plan

  variables {
    guardduty_detector_id   = "12abc34d567e8fa901bc2d34e56789f0"
    securityhub_account_arn = "arn:aws:securityhub:eu-west-2:123456789012:hub/default"
  }

  assert {
    condition     = length(aws_cloudwatch_event_rule.guardduty_findings) == 1 && length(aws_cloudwatch_event_rule.securityhub_findings) == 1
    error_message = "Both finding routes must exist when the detector ID and hub ARN are passed in."
  }

  assert {
    condition     = jsondecode(aws_cloudwatch_event_rule.guardduty_findings[0].event_pattern).detail.severity[0].numeric == [">=", 4]
    error_message = "GuardDuty findings must be routed from severity 4.0 up, CRITICAL (9.0-10.0) included."
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

run "null_ids_disable_routes" {
  command = plan

  assert {
    condition     = length(aws_cloudwatch_event_rule.guardduty_findings) == 0 && length(aws_cloudwatch_metric_alarm.guardduty_high_findings) == 0
    error_message = "Without a detector ID there must be no GuardDuty route or alarm."
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
