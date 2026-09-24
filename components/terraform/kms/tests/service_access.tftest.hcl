# The key policy's service statements. The real AWS provider is used, not a
# mock: aws_iam_policy_document is computed locally, and a mock would return
# a random string instead of the policy. It never reaches AWS: credentials
# are dummies, every check that would call AWS is skipped, and the one data
# source that needs an API call (caller identity) is overridden.
# Run: terraform init -backend=false && terraform test

provider "aws" {
  region                      = "eu-west-2"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
}

override_data {
  target = module.kms.data.aws_caller_identity.current
  values = {
    account_id = "123456789012"
  }
}

variables {
  region      = "eu-west-2"
  name_prefix = "fnx-dev-test"
  tags = {
    Environment = "test"
  }
}

run "no_service_statements_by_default" {
  command = plan

  assert {
    condition = length([
      for s in jsondecode(module.kms.key_policy).Statement : s
      if contains(["AllowCloudWatchLogs", "AllowEventBridge", "AllowEventBridgeDescribeKey", "AllowEventBridgeSNSTopics", "AllowCloudWatchAlarmsSNSTopics"], try(s.Sid, ""))
    ]) == 0
    error_message = "Service statements are opt-in."
  }
}

run "logs_and_events_are_scoped_to_this_account_and_region" {
  command = plan

  variables {
    allow_cloudwatch_logs   = true
    allow_eventbridge       = true
    allow_cloudwatch_alarms = true
  }

  assert {
    condition     = one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowCloudWatchLogs"]).Principal.Service == "logs.eu-west-2.amazonaws.com"
    error_message = "CloudWatch Logs is the regional logs principal."
  }

  assert {
    condition     = one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowCloudWatchLogs"]).Condition.ArnLike["kms:EncryptionContext:aws:logs:arn"] == "arn:aws:logs:eu-west-2:123456789012:log-group:*"
    error_message = "CloudWatch Logs may use the key only for this account's log groups in this region."
  }

  # Bus and archive crypto is scoped by the event-bus encryption context, which
  # archive calls always carry (they carry no aws:SourceArn).
  assert {
    condition     = one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowEventBridge"]).Condition == { ArnLike = { "kms:EncryptionContext:aws:events:event-bus:arn" = "arn:aws:events:eu-west-2:123456789012:event-bus/*" } }
    error_message = "EventBridge bus/archive crypto must be conditioned only on kms:EncryptionContext:aws:events:event-bus:arn for this account's buses in this region."
  }

  assert {
    condition     = !contains(flatten([one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowEventBridge"]).Action]), "kms:DescribeKey")
    error_message = "kms:DescribeKey has no encryption context, so it must not sit in the context-scoped statement."
  }

  assert {
    condition = (
      one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowEventBridgeDescribeKey"]).Action == "kms:DescribeKey"
      && one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowEventBridgeDescribeKey"]).Condition == { StringEquals = { "aws:SourceAccount" = "123456789012" } }
    )
    error_message = "EventBridge DescribeKey is its own statement, limited to this account by aws:SourceAccount only."
  }

  assert {
    condition = alltrue([
      for sid, principal in {
        AllowEventBridgeSNSTopics      = "events.amazonaws.com"
        AllowCloudWatchAlarmsSNSTopics = "cloudwatch.amazonaws.com"
      } :
      one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == sid]).Principal.Service == principal
      && toset(one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == sid]).Action) == toset(["kms:GenerateDataKey*", "kms:Decrypt"])
      && one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == sid]).Condition.StringEquals["aws:SourceAccount"] == "123456789012"
      && one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == sid]).Condition.ArnLike["kms:EncryptionContext:aws:sns:topicArn"] == "arn:aws:sns:eu-west-2:123456789012:*"
    ])
    error_message = "EventBridge rules and CloudWatch alarms may use kms:GenerateDataKey*/kms:Decrypt only for this account's SNS topics in this region, and only for this account (aws:SourceAccount)."
  }
}

run "cloudwatch_alarms_flag_is_independent" {
  command = plan

  variables {
    allow_cloudwatch_alarms = true
  }

  assert {
    condition     = length([for s in jsondecode(module.kms.key_policy).Statement : s if startswith(try(s.Sid, ""), "AllowEventBridge")]) == 0
    error_message = "allow_cloudwatch_alarms must not grant EventBridge anything."
  }

  assert {
    condition     = length([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowCloudWatchAlarmsSNSTopics"]) == 1
    error_message = "allow_cloudwatch_alarms adds the CloudWatch alarms SNS statement."
  }
}
