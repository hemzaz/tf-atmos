# security-monitoring routes GuardDuty, Security Hub and Inspector findings; it
# never creates the services and reads none of their state.
#
# The region's delegated administrator in the security account (vendored
# aws-guardduty, aws-security-hub, aws-inspector2 org-settings) enrolls the
# account; the member's detector and hub publish its own findings to its own
# EventBridge. Stacks pass one flag per route (owner OQ-AL). These runs prove
# that the routes are on by default with no service input at all, that turning
# GuardDuty or Security Hub off fails the plan unless its require_*_route is
# cleared too, that clearing both turns the route off, and that the Inspector
# route follows its flag alone.
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
      arn = "arn:aws:sns:us-east-1:123456789012:test-security-alerts"
    }
  }
}

variables {
  region = "us-east-1"
  tags = {
    Environment = "test"
    Tenant      = "fnx"
    ManagedBy   = "Terraform"
  }
  kms_key_id                = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
  cloudtrail_log_group_name = "/aws/cloudtrail/test-cloudtrail"
}

run "routes_member_findings_by_default" {
  command = plan

  assert {
    condition     = length(aws_cloudwatch_event_rule.guardduty_findings) == 1 && length(aws_cloudwatch_event_rule.securityhub_findings) == 1 && length(aws_cloudwatch_event_rule.inspector_findings) == 1
    error_message = "The GuardDuty, Security Hub and Inspector routes must default on, with no detector, hub or account input."
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
    condition = (
      jsondecode(aws_cloudwatch_event_rule.inspector_findings[0].event_pattern).source == ["aws.inspector2"]
      && jsondecode(aws_cloudwatch_event_rule.inspector_findings[0].event_pattern).detail.severity == ["HIGH", "CRITICAL"]
    )
    error_message = "The Inspector route matches HIGH and CRITICAL Inspector2 findings."
  }

  # The rules match on the service events only, never on an account: a member
  # receives its own findings in its own EventBridge, so no account filter is
  # needed (and one would drop them).
  assert {
    condition = alltrue([
      for p in [
        jsondecode(aws_cloudwatch_event_rule.guardduty_findings[0].event_pattern),
        jsondecode(aws_cloudwatch_event_rule.securityhub_findings[0].event_pattern),
        jsondecode(aws_cloudwatch_event_rule.inspector_findings[0].event_pattern),
      ] : !contains(keys(p), "account") && !contains(keys(p.detail), "accountId")
    ])
    error_message = "The finding routes must not filter on an account."
  }

  assert {
    condition     = aws_sns_topic.security_alerts.kms_master_key_id == var.kms_key_id
    error_message = "The alert topic must be encrypted with the key passed in (kms/main)."
  }
}

run "cis_filters_feed_the_cloudtrail_alarms" {
  command = plan

  assert {
    condition     = length(aws_cloudwatch_log_metric_filter.cloudtrail) == 4
    error_message = "One CIS metric filter per CloudTrailMetrics alarm."
  }

  assert {
    condition     = alltrue([for f in aws_cloudwatch_log_metric_filter.cloudtrail : f.log_group_name == "/aws/cloudtrail/test-cloudtrail"])
    error_message = "Every filter must read the trail's CloudWatch log group."
  }

  assert {
    condition = alltrue([
      for pair in [
        [aws_cloudwatch_metric_alarm.root_account_usage[0], aws_cloudwatch_log_metric_filter.cloudtrail["root_account_usage"]],
        [aws_cloudwatch_metric_alarm.unauthorized_api_calls[0], aws_cloudwatch_log_metric_filter.cloudtrail["unauthorized_api_calls"]],
        [aws_cloudwatch_metric_alarm.iam_policy_changes[0], aws_cloudwatch_log_metric_filter.cloudtrail["iam_policy_changes"]],
        [aws_cloudwatch_metric_alarm.security_group_changes[0], aws_cloudwatch_log_metric_filter.cloudtrail["security_group_changes"]],
      ] :
      pair[0].namespace == one(pair[1].metric_transformation).namespace && pair[0].metric_name == one(pair[1].metric_transformation).name
    ])
    error_message = "Each alarm must watch exactly the metric its filter publishes (namespace and name)."
  }

  assert {
    condition     = strcontains(aws_cloudwatch_log_metric_filter.cloudtrail["root_account_usage"].pattern, "$.userIdentity.type=\"Root\"") && strcontains(aws_cloudwatch_log_metric_filter.cloudtrail["root_account_usage"].pattern, "$.userIdentity.invokedBy NOT EXISTS")
    error_message = "The root filter is the CIS pattern (root identity, not invoked by a service)."
  }
}

run "topic_policy_is_same_account_only" {
  command = apply

  assert {
    condition = length(aws_cloudwatch_event_target.guardduty_sns) == 1 && length(aws_cloudwatch_event_target.securityhub_sns) == 1 && length(aws_cloudwatch_event_target.inspector_sns) == 1 && alltrue([
      for t in concat(aws_cloudwatch_event_target.guardduty_sns, aws_cloudwatch_event_target.securityhub_sns, aws_cloudwatch_event_target.inspector_sns) :
      t.arn == aws_sns_topic.security_alerts.arn
    ])
    error_message = "Each finding route must target the alert topic."
  }

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
    ]) == "arn:aws:events:us-east-1:123456789012:rule/*"
    error_message = "EventBridge may publish only from this account's rules in this region."
  }

  assert {
    condition = one([
      for s in jsondecode(aws_sns_topic_policy.security_alerts.policy).Statement :
      s.Condition.ArnLike["aws:SourceArn"] if s.Principal.Service == "cloudwatch.amazonaws.com"
    ]) == "arn:aws:cloudwatch:us-east-1:123456789012:alarm:*"
    error_message = "CloudWatch may publish only from this account's alarms in this region."
  }
}

run "guardduty_route_off_fails_while_required" {
  command = plan

  variables {
    enable_guardduty_route = false
  }

  expect_failures = [aws_sns_topic.security_alerts]
}

run "securityhub_route_off_fails_while_required" {
  command = plan

  variables {
    enable_securityhub_route = false
  }

  expect_failures = [aws_sns_topic.security_alerts]
}

run "null_log_group_fails_when_route_required" {
  command = plan

  variables {
    cloudtrail_log_group_name = null
  }

  expect_failures = [aws_sns_topic.security_alerts]
}

run "routes_off_with_both_flags_cleared" {
  command = plan

  variables {
    enable_guardduty_route    = false
    enable_securityhub_route  = false
    enable_inspector2_route   = false
    cloudtrail_log_group_name = null
    require_guardduty_route   = false
    require_securityhub_route = false
    require_cloudtrail_route  = false
  }

  assert {
    condition     = length(aws_cloudwatch_log_metric_filter.cloudtrail) == 0 && length(aws_cloudwatch_metric_alarm.root_account_usage) == 0
    error_message = "Without a CloudTrail log group there must be no CIS filters or alarms watching unpublished metrics."
  }

  assert {
    condition     = length(aws_cloudwatch_event_rule.guardduty_findings) == 0 && length(aws_cloudwatch_event_target.guardduty_sns) == 0
    error_message = "With enable_guardduty_route false there must be no GuardDuty route."
  }

  assert {
    condition     = length(aws_cloudwatch_event_rule.securityhub_findings) == 0 && length(aws_cloudwatch_event_target.securityhub_sns) == 0
    error_message = "With enable_securityhub_route false there must be no Security Hub route."
  }

  assert {
    condition     = output.guardduty_event_rule_arn == null && output.securityhub_event_rule_arn == null && output.inspector_event_rule_arn == null
    error_message = "The rule ARN outputs must be null without their routes."
  }
}

run "inspector_route_off_needs_only_its_flag" {
  command = plan

  variables {
    enable_inspector2_route = false
  }

  assert {
    condition     = length(aws_cloudwatch_event_rule.inspector_findings) == 0 && length(aws_cloudwatch_event_target.inspector_sns) == 0
    error_message = "enable_inspector2_route false turns the Inspector route off, and no plan failure (no require_* switch)."
  }

  assert {
    condition     = length(aws_cloudwatch_event_rule.guardduty_findings) == 1 && length(aws_cloudwatch_event_rule.securityhub_findings) == 1
    error_message = "The Inspector flag must not touch the GuardDuty or Security Hub route."
  }
}

# nullable = false: a null from a stack (an unset or failed lookup) takes the
# default, so it can never turn a route off.
run "null_route_flags_keep_the_routes_on" {
  command = plan

  variables {
    enable_guardduty_route   = null
    enable_securityhub_route = null
    enable_inspector2_route  = null
  }

  assert {
    condition     = length(aws_cloudwatch_event_rule.guardduty_findings) == 1 && length(aws_cloudwatch_event_rule.securityhub_findings) == 1 && length(aws_cloudwatch_event_rule.inspector_findings) == 1
    error_message = "A null route flag must keep its route on (the default)."
  }
}

run "rejects_non_arn_kms_key" {
  command = plan

  variables {
    kms_key_id = "alias/main"
  }

  expect_failures = [var.kms_key_id]
}
