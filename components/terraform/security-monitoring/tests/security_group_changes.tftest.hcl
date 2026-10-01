# Security group change detection, moved here from the securitygroup component.
#
# securitygroup used to create, per instance, an EventBridge rule with no
# target, a space-delimited metric filter that never matches CloudTrail's JSON,
# an unencrypted log group, and names that collided between instances. These
# runs prove the account-level replacement actually reaches the alert topic:
# the rule has an SNS target, the CIS filter is the JSON form and reads the
# trail's (CMK-encrypted, owned by cloudtrail) log group, the topic is
# encrypted with the CMK, and the names carry the per-stack prefix.
#
# Applied against the mock provider so the topic ARN is known in the target.

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
  enable_inspector          = false
  guardduty_detector_id     = "12abc34d567e8fa901bc2d34e56789f0"
  securityhub_account_arn   = "arn:aws:securityhub:eu-west-2:123456789012:hub/default"
  kms_key_id                = "arn:aws:kms:eu-west-2:123456789012:key/12345678-1234-1234-1234-123456789012"
  cloudtrail_log_group_name = "/aws/cloudtrail/test-cloudtrail"
}

run "security_group_changes_reach_the_alert_topic" {
  command = apply

  assert {
    condition     = length(aws_cloudwatch_event_rule.security_group_changes) == 1 && length(aws_cloudwatch_event_target.security_group_changes_sns) == 1
    error_message = "The security group change rule must exist with a target; a rule without one matches and does nothing."
  }

  assert {
    condition     = aws_cloudwatch_event_target.security_group_changes_sns[0].arn == aws_sns_topic.security_alerts.arn && aws_cloudwatch_event_target.security_group_changes_sns[0].arn == "arn:aws:sns:eu-west-2:123456789012:test-security-alerts"
    error_message = "The rule's target must be the stack's security alert topic."
  }

  assert {
    condition     = aws_cloudwatch_event_target.security_group_changes_sns[0].rule == aws_cloudwatch_event_rule.security_group_changes[0].name
    error_message = "The SNS target must be attached to the security group change rule."
  }

  assert {
    condition     = aws_sns_topic.security_alerts.kms_master_key_id == var.kms_key_id
    error_message = "The topic the changes are delivered to must be encrypted with the CMK (kms/main)."
  }

  assert {
    condition = (
      jsondecode(aws_cloudwatch_event_rule.security_group_changes[0].event_pattern).source == ["aws.ec2"]
      && jsondecode(aws_cloudwatch_event_rule.security_group_changes[0].event_pattern)["detail-type"] == ["AWS API Call via CloudTrail"]
      && jsondecode(aws_cloudwatch_event_rule.security_group_changes[0].event_pattern).detail.eventSource == ["ec2.amazonaws.com"]
    )
    error_message = "The rule must match EC2 API calls recorded by CloudTrail."
  }

  assert {
    condition = alltrue([
      for e in ["AuthorizeSecurityGroupIngress", "AuthorizeSecurityGroupEgress", "RevokeSecurityGroupIngress", "RevokeSecurityGroupEgress", "CreateSecurityGroup", "DeleteSecurityGroup", "ModifySecurityGroupRules"] :
      contains(jsondecode(aws_cloudwatch_event_rule.security_group_changes[0].event_pattern).detail.eventName, e)
    ])
    error_message = "The rule must match every security group create, delete and rule change, ModifySecurityGroupRules included."
  }

  assert {
    condition     = aws_cloudwatch_event_rule.security_group_changes[0].name == "test-security-security-group-changes"
    error_message = "The rule name must carry the per-stack name prefix (<Environment>-<Name>), so one instance per account and region cannot collide."
  }

  assert {
    condition     = contains(aws_cloudwatch_metric_alarm.security_group_changes[0].alarm_actions, aws_sns_topic.security_alerts.arn)
    error_message = "The CIS SecurityGroupChanges alarm must notify the same alert topic."
  }

  assert {
    condition     = output.security_group_change_rule_arn == aws_cloudwatch_event_rule.security_group_changes[0].arn
    error_message = "security_group_change_rule_arn must expose the rule."
  }
}

run "cis_security_group_filter_is_json_on_the_trail_log_group" {
  command = plan

  assert {
    condition     = startswith(aws_cloudwatch_log_metric_filter.cloudtrail["security_group_changes"].pattern, "{") && endswith(aws_cloudwatch_log_metric_filter.cloudtrail["security_group_changes"].pattern, "}")
    error_message = "The security group change filter must be a JSON filter: a space-delimited pattern never matches CloudTrail's JSON events."
  }

  assert {
    condition = alltrue([
      for e in ["AuthorizeSecurityGroupIngress", "AuthorizeSecurityGroupEgress", "RevokeSecurityGroupIngress", "RevokeSecurityGroupEgress", "CreateSecurityGroup", "DeleteSecurityGroup"] :
      strcontains(aws_cloudwatch_log_metric_filter.cloudtrail["security_group_changes"].pattern, "($.eventName=${e})")
    ])
    error_message = "The filter must be the CIS pattern over $.eventName for all six security group API calls."
  }

  assert {
    condition     = aws_cloudwatch_log_metric_filter.cloudtrail["security_group_changes"].log_group_name == var.cloudtrail_log_group_name
    error_message = "The filter must read the account trail's log group (encrypted with kms/main by the cloudtrail component)."
  }

  assert {
    condition     = aws_cloudwatch_log_metric_filter.cloudtrail["security_group_changes"].name == "test-security-security-group-changes"
    error_message = "The filter name must carry the per-stack name prefix."
  }
}

run "security_group_change_events_can_be_turned_off" {
  command = plan

  variables {
    enable_security_group_change_events = false
  }

  assert {
    condition     = length(aws_cloudwatch_event_rule.security_group_changes) == 0 && length(aws_cloudwatch_event_target.security_group_changes_sns) == 0
    error_message = "enable_security_group_change_events = false must remove the rule and its target."
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.security_group_changes) == 1
    error_message = "Turning the per-change rule off must leave the CIS alarm in place."
  }
}

# Automation exclusion. anything-but does not match an event that lacks the
# field, so a pattern with only the anything-but branch would silently drop
# root, IAM user and AWS service calls (no sessionIssuer). These runs pin the
# two-branch $or: excluded roles in one branch, {"exists": false} in the other.
run "automation_roles_are_excluded_but_principals_without_session_issuer_still_alert" {
  command = plan

  variables {
    security_group_change_excluded_role_arns = [
      "arn:aws:iam::123456789012:role/test-main-aws-load-balancer-controller-role",
      "arn:aws:iam::123456789012:role/aws-service-role/eks.amazonaws.com/AWSServiceRoleForAmazonEKS",
      "arn:aws:iam::123456789012:role/test-main-aws-load-balancer-controller-role",
      null,
    ]
  }

  assert {
    condition     = length(jsondecode(aws_cloudwatch_event_rule.security_group_changes[0].event_pattern).detail["$or"]) == 2
    error_message = "The principal filter must be an $or of exactly two branches."
  }

  assert {
    condition = (
      jsondecode(aws_cloudwatch_event_rule.security_group_changes[0].event_pattern).detail["$or"][0].userIdentity.sessionContext.sessionIssuer.arn[0]["anything-but"]
      == [
        "arn:aws:iam::123456789012:role/test-main-aws-load-balancer-controller-role",
        "arn:aws:iam::123456789012:role/aws-service-role/eks.amazonaws.com/AWSServiceRoleForAmazonEKS",
      ]
    )
    error_message = "The first branch must exclude every listed role ARN on sessionIssuer.arn, once each, nulls dropped."
  }

  assert {
    condition     = jsondecode(aws_cloudwatch_event_rule.security_group_changes[0].event_pattern).detail["$or"][1].userIdentity.sessionContext.sessionIssuer.arn[0].exists == false
    error_message = "The second branch must match events without a sessionIssuer (root, IAM users, AWS services); anything-but alone never matches a missing field."
  }

  assert {
    condition = (
      jsondecode(aws_cloudwatch_event_rule.security_group_changes[0].event_pattern).detail.eventSource == ["ec2.amazonaws.com"]
      && contains(jsondecode(aws_cloudwatch_event_rule.security_group_changes[0].event_pattern).detail.eventName, "ModifySecurityGroupRules")
    )
    error_message = "The principal filter must sit beside the event filter, not replace it."
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.security_group_changes) == 1 && !strcontains(aws_cloudwatch_log_metric_filter.cloudtrail["security_group_changes"].pattern, "userIdentity")
    error_message = "The CIS SecurityGroupChanges filter and alarm must keep counting every change, automation included."
  }
}

run "no_excluded_roles_means_no_principal_filter" {
  command = plan

  variables {
    security_group_change_excluded_role_arns = [null]
  }

  assert {
    condition     = !contains(keys(jsondecode(aws_cloudwatch_event_rule.security_group_changes[0].event_pattern).detail), "$or")
    error_message = "With no excluded roles the pattern must carry no principal filter (an empty anything-but list is invalid)."
  }
}

run "excluded_role_arns_reject_wildcards" {
  command = plan

  variables {
    security_group_change_excluded_role_arns = ["arn:aws:iam::123456789012:role/*"]
  }

  expect_failures = [var.security_group_change_excluded_role_arns]
}

run "excluded_role_arns_reject_user_arns" {
  command = plan

  variables {
    security_group_change_excluded_role_arns = ["arn:aws:iam::123456789012:user/alice"]
  }

  expect_failures = [var.security_group_change_excluded_role_arns]
}
