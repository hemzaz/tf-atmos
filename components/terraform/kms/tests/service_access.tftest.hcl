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
      if contains(["AllowCloudWatchLogs", "AllowLogDelivery", "AllowEventBridge", "AllowEventBridgeDescribeKey", "AllowEventBridgeSNSTopics", "AllowEventBridgeSQSQueues", "AllowCloudWatchAlarmsSNSTopics", "AllowCloudTrailEncryptLogs", "AllowCloudTrailDecrypt", "AllowCloudTrailDescribeKey", "AllowSNS", "AllowS3"], try(s.Sid, ""))
    ]) == 0
    error_message = "Service statements are opt-in."
  }
}

run "log_delivery_is_scoped_to_this_account" {
  command = plan

  variables {
    allow_log_delivery = true
  }

  assert {
    condition = (
      one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowLogDelivery"]).Principal.Service == "delivery.logs.amazonaws.com"
      && one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowLogDelivery"]).Action == "kms:Decrypt"
      && one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowLogDelivery"]).Condition == { StringEquals = { "aws:SourceAccount" = "123456789012" } }
    )
    error_message = "delivery.logs.amazonaws.com may kms:Decrypt only for this account (aws:SourceAccount); it is a distinct principal from logs.<region>.amazonaws.com (allow_cloudwatch_logs)."
  }

  assert {
    condition     = length([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowCloudWatchLogs"]) == 0
    error_message = "allow_log_delivery must not grant AllowCloudWatchLogs; the two flags are independent."
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

  # EventBridge-to-encrypted-topic delivery fails if the KMS policy carries
  # aws:SourceAccount/aws:SourceArn (SNS docs), so only the encryption context
  # scopes it. CloudWatch supports aws:SourceAccount and keeps it.
  assert {
    condition = (
      one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowEventBridgeSNSTopics"]).Principal.Service == "events.amazonaws.com"
      && toset(one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowEventBridgeSNSTopics"]).Action) == toset(["kms:GenerateDataKey*", "kms:Decrypt"])
      && one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowEventBridgeSNSTopics"]).Condition == { ArnLike = { "kms:EncryptionContext:aws:sns:topicArn" = "arn:aws:sns:eu-west-2:123456789012:*" } }
    )
    error_message = "EventBridge may use kms:GenerateDataKey*/kms:Decrypt only for this account's SNS topics in this region, conditioned on the SNS encryption context alone (no aws:Source* keys, which break EventBridge delivery)."
  }

  # Rules and bus DLQs delivering to SSE-KMS SQS queues carry no bus or topic
  # encryption context, so the source keys scope the grant: a rule target's
  # aws:SourceArn is the rule, a bus DLQ's is the bus.
  assert {
    condition = (
      one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowEventBridgeSQSQueues"]).Principal.Service == "events.amazonaws.com"
      && toset(one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowEventBridgeSQSQueues"]).Action) == toset(["kms:GenerateDataKey", "kms:Decrypt"])
      && toset(keys(one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowEventBridgeSQSQueues"]).Condition)) == toset(["StringEquals", "ArnLike"])
      && one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowEventBridgeSQSQueues"]).Condition.StringEquals == { "aws:SourceAccount" = "123456789012" }
      && toset(keys(one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowEventBridgeSQSQueues"]).Condition.ArnLike)) == toset(["aws:SourceArn"])
      && toset(one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowEventBridgeSQSQueues"]).Condition.ArnLike["aws:SourceArn"]) == toset([
        "arn:aws:events:eu-west-2:123456789012:rule/*",
        "arn:aws:events:eu-west-2:123456789012:event-bus/*",
      ])
    )
    error_message = "EventBridge may use kms:GenerateDataKey/kms:Decrypt for SQS queues only from this account's rules (targets) and buses (bus DLQs) in this region (aws:SourceAccount and aws:SourceArn), and under no other condition."
  }

  assert {
    condition = (
      one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowCloudWatchAlarmsSNSTopics"]).Principal.Service == "cloudwatch.amazonaws.com"
      && toset(one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowCloudWatchAlarmsSNSTopics"]).Action) == toset(["kms:GenerateDataKey*", "kms:Decrypt"])
      && one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowCloudWatchAlarmsSNSTopics"]).Condition == {
        StringEquals = { "aws:SourceAccount" = "123456789012" }
        ArnLike      = { "kms:EncryptionContext:aws:sns:topicArn" = "arn:aws:sns:eu-west-2:123456789012:*" }
      }
    )
    error_message = "CloudWatch alarms may use kms:GenerateDataKey*/kms:Decrypt only for this account's SNS topics in this region, and only for this account (aws:SourceAccount)."
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

run "sns_delivers_to_queues_only_for_this_accounts_topics" {
  command = plan

  variables {
    allow_sns = true
  }

  assert {
    condition = (
      one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowSNS"]).Principal.Service == "sns.amazonaws.com"
      && toset(one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowSNS"]).Action) == toset(["kms:Decrypt", "kms:GenerateDataKey*"])
      && one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowSNS"]).Condition == {
        StringEquals = { "aws:SourceAccount" = "123456789012" }
        ArnLike      = { "aws:SourceArn" = "arn:aws:sns:eu-west-2:123456789012:*" }
      }
    )
    error_message = "SNS may use kms:Decrypt/kms:GenerateDataKey* only for this account's topics in this region (aws:SourceAccount and aws:SourceArn)."
  }

  assert {
    condition     = length([for s in jsondecode(module.kms.key_policy).Statement : s if startswith(try(s.Sid, ""), "AllowEventBridge") || startswith(try(s.Sid, ""), "AllowCloudWatch")]) == 0
    error_message = "allow_sns must not grant other services anything."
  }
}

run "s3_notifies_encrypted_queues_only_for_this_accounts_buckets" {
  command = plan

  variables {
    allow_s3 = true
  }

  assert {
    condition = (
      one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowS3"]).Principal.Service == "s3.amazonaws.com"
      && toset(one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowS3"]).Action) == toset(["kms:Decrypt", "kms:GenerateDataKey*"])
      && one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowS3"]).Condition == {
        StringEquals = { "aws:SourceAccount" = "123456789012" }
        ArnLike      = { "aws:SourceArn" = "arn:aws:s3:::*" }
      }
    )
    error_message = "S3 may use kms:Decrypt/kms:GenerateDataKey* only for this account's buckets (aws:SourceAccount and aws:SourceArn)."
  }

  assert {
    condition     = length([for s in jsondecode(module.kms.key_policy).Statement : s if contains(["AllowSNS", "AllowCloudWatchLogs", "AllowCloudTrailEncryptLogs"], try(s.Sid, "")) || startswith(try(s.Sid, ""), "AllowEventBridge")]) == 0
    error_message = "allow_s3 must not grant other services anything."
  }
}

run "cloudtrail_is_scoped_to_this_accounts_trails" {
  command = plan

  variables {
    allow_cloudtrail = true
  }

  assert {
    condition = (
      one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowCloudTrailEncryptLogs"]).Action == "kms:GenerateDataKey*"
      && one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowCloudTrailEncryptLogs"]).Principal.Service == "cloudtrail.amazonaws.com"
      && one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowCloudTrailEncryptLogs"]).Condition.StringLike["kms:EncryptionContext:aws:cloudtrail:arn"] == "arn:aws:cloudtrail:*:123456789012:trail/*"
      && one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowCloudTrailEncryptLogs"]).Condition.ArnLike["aws:SourceArn"] == "arn:aws:cloudtrail:eu-west-2:123456789012:trail/*"
    )
    error_message = "CloudTrail may only generate data keys for this account's trails (encryption context and aws:SourceArn)."
  }

  assert {
    condition = (
      one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowCloudTrailDescribeKey"]).Action == "kms:DescribeKey"
      && one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowCloudTrailDescribeKey"]).Condition == { ArnLike = { "aws:SourceArn" = "arn:aws:cloudtrail:eu-west-2:123456789012:trail/*" } }
    )
    error_message = "CloudTrail DescribeKey is limited to this account's trails in this region."
  }

  # The trail bucket uses an S3 Bucket Key, which needs kms:Decrypt for the
  # CloudTrail principal.
  assert {
    condition = (
      one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowCloudTrailDecrypt"]).Action == "kms:Decrypt"
      && one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowCloudTrailDecrypt"]).Principal.Service == "cloudtrail.amazonaws.com"
      && one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowCloudTrailDecrypt"]).Condition == { ArnLike = { "aws:SourceArn" = "arn:aws:cloudtrail:eu-west-2:123456789012:trail/*" } }
    )
    error_message = "CloudTrail may kms:Decrypt (S3 Bucket Key) only for this account's trails in this region (aws:SourceArn)."
  }

  assert {
    condition     = length([for s in jsondecode(module.kms.key_policy).Statement : s if contains(["AllowEventBridge", "AllowCloudWatchLogs", "AllowCloudWatchAlarmsSNSTopics"], try(s.Sid, ""))]) == 0
    error_message = "allow_cloudtrail must not grant other services anything."
  }
}
