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
    condition     = length([for s in jsondecode(module.kms.key_policy).Statement : s if contains(["AllowCloudWatchLogs", "AllowEventBridge"], try(s.Sid, ""))]) == 0
    error_message = "Service statements are opt-in."
  }
}

run "logs_and_events_are_scoped_to_this_account_and_region" {
  command = plan

  variables {
    allow_cloudwatch_logs = true
    allow_eventbridge     = true
  }

  assert {
    condition     = one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowCloudWatchLogs"]).Principal.Service == "logs.eu-west-2.amazonaws.com"
    error_message = "CloudWatch Logs is the regional logs principal."
  }

  assert {
    condition     = one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowCloudWatchLogs"]).Condition.ArnLike["kms:EncryptionContext:aws:logs:arn"] == "arn:aws:logs:eu-west-2:123456789012:log-group:*"
    error_message = "CloudWatch Logs may use the key only for this account's log groups in this region."
  }

  assert {
    condition     = one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowEventBridge"]).Condition.StringEquals["aws:SourceAccount"] == "123456789012"
    error_message = "EventBridge is limited to this account (aws:SourceAccount)."
  }

  assert {
    condition = toset(one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowEventBridge"]).Condition.ArnLike["aws:SourceArn"]) == toset([
      "arn:aws:events:eu-west-2:123456789012:event-bus/*",
      "arn:aws:events:eu-west-2:123456789012:archive/*",
    ])
    error_message = "EventBridge is limited to this account's buses and archives in this region (aws:SourceArn)."
  }
}
