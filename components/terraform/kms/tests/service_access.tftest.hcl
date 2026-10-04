# The key policy's service statements. The real AWS provider is used, not a
# mock: aws_iam_policy_document is computed locally, and a mock would return
# a random string instead of the policy. It never reaches AWS: credentials
# are dummies, every check that would call AWS is skipped, and the one data
# source that needs an API call (caller identity) is overridden.
# Run: terraform init -backend=false && terraform test

provider "aws" {
  region                      = "us-east-1"
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
  region      = "us-east-1"
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
      if contains(["AllowCloudWatchLogs", "AllowLogDelivery", "AllowLogDeliveryDataKeys", "AllowEventBridge", "AllowEventBridgeDescribeKey", "AllowEventBridgeSNSTopics", "AllowEventBridgeSQSQueues", "AllowCloudWatchAlarmsSNSTopics", "AllowCloudTrailEncryptLogs", "AllowCloudTrailDecrypt", "AllowCloudTrailDescribeKey", "AllowSNS", "AllowS3", "AllowAutoScalingEBSUsage", "AllowAutoScalingEBSGrant", "AllowBackupSNSTopics", "AllowCloudFront", "AllowLogDeliveryToS3"], try(s.Sid, ""))
    ]) == 0
    error_message = "Service statements are opt-in."
  }
}

run "autoscaling_ebs_grants_the_service_linked_role" {
  command = plan

  variables {
    allow_autoscaling_ebs = true
  }

  assert {
    condition = (
      # The principal is the service-linked role itself, not the account
      # root: a root-principal statement would grant nothing to this role by
      # itself (AWS's key-policy docs: an account-principal statement only
      # lets the account delegate access through IAM identity policies, and
      # this role's AWS-managed policy carries no customer-managed-key
      # permissions), so an aws:PrincipalArn condition narrowing a root
      # principal back down to this role's ARN would be a no-op grant. `iam`
      # provisions the role first (enable_autoscaling_service_linked_role)
      # so KMS's principal-existence check at CreateKey/PutKeyPolicy time
      # passes.
      one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowAutoScalingEBSUsage"]).Principal.AWS == "arn:aws:iam::123456789012:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"
      && toset(one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowAutoScalingEBSUsage"]).Action) == toset(["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey"])
      && one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowAutoScalingEBSUsage"]).Condition == {
        StringEquals = {
          "kms:ViaService"    = "ec2.us-east-1.amazonaws.com"
          "kms:CallerAccount" = "123456789012"
        }
      }
    )
    error_message = "The Auto Scaling service-linked role may use the key only via EC2 in this region, and only for this account; the principal must be the role itself, not an account-root principal narrowed by aws:PrincipalArn (which would not actually grant the role anything)."
  }

  assert {
    condition = (
      one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowAutoScalingEBSGrant"]).Principal.AWS == "arn:aws:iam::123456789012:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"
      && one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowAutoScalingEBSGrant"]).Action == "kms:CreateGrant"
      && one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowAutoScalingEBSGrant"]).Condition == { Bool = { "kms:GrantIsForAWSResource" = "true" } }
    )
    error_message = "The Auto Scaling service-linked role may create a grant only for an AWS resource (EBS), never an arbitrary grantee."
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

  assert {
    condition = (
      one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowLogDeliveryDataKeys"]).Principal.Service == "delivery.logs.amazonaws.com"
      && one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowLogDeliveryDataKeys"]).Action == "kms:GenerateDataKey*"
      && one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowLogDeliveryDataKeys"]).Condition.StringEquals["aws:SourceAccount"] == "123456789012"
      && startswith(one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowLogDeliveryDataKeys"]).Condition.ArnLike["aws:SourceArn"], "arn:aws:logs:")
      && endswith(one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowLogDeliveryDataKeys"]).Condition.ArnLike["aws:SourceArn"], ":123456789012:*")
    )
    error_message = "allow_log_delivery must let delivery.logs.amazonaws.com kms:GenerateDataKey* (vended logs into SSE-KMS S3, e.g. the vpc flow-log copy), scoped to this account and its CloudWatch Logs source ARNs."
  }
}

run "log_delivery_off_grants_nothing" {
  command = plan

  variables {
    allow_log_delivery = false
  }

  assert {
    condition = length([
      for s in jsondecode(module.kms.key_policy).Statement : s
      if contains(["AllowLogDelivery", "AllowLogDeliveryDataKeys"], try(s.Sid, ""))
    ]) == 0
    error_message = "With allow_log_delivery off, delivery.logs.amazonaws.com gets no statement (no Decrypt, no GenerateDataKey*)."
  }
}

run "log_delivery_to_s3_is_scoped_to_this_accounts_delivery_sources" {
  command = plan

  variables {
    allow_log_delivery_s3 = true
  }

  assert {
    condition = (
      one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowLogDeliveryToS3"]).Principal.Service == "delivery.logs.amazonaws.com"
      && toset(one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowLogDeliveryToS3"]).Action) == toset(["kms:GenerateDataKey*", "kms:Decrypt"])
      && one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowLogDeliveryToS3"]).Condition == {
        StringEquals = { "aws:SourceAccount" = "123456789012" }
        ArnLike      = { "aws:SourceArn" = "arn:aws:logs:*:123456789012:delivery-source:*" }
      }
    )
    error_message = "delivery.logs.amazonaws.com may generate data keys and decrypt only for this account's delivery sources (vended logs to an SSE-KMS bucket)."
  }

  assert {
    condition     = length([for s in jsondecode(module.kms.key_policy).Statement : s if contains(["AllowLogDelivery", "AllowLogDeliveryDataKeys", "AllowS3", "AllowCloudWatchLogs"], try(s.Sid, ""))]) == 0
    error_message = "allow_log_delivery_s3 must not grant the other log or S3 statements."
  }
}

run "cloudfront_is_scoped_to_this_accounts_distributions" {
  command = plan

  variables {
    allow_cloudfront = true
  }

  assert {
    condition = (
      one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowCloudFront"]).Principal.Service == "cloudfront.amazonaws.com"
      && one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowCloudFront"]).Action == "kms:Decrypt"
      && one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowCloudFront"]).Resource == "*"
      && one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowCloudFront"]).Condition == {
        StringEquals = { "aws:SourceAccount" = "123456789012" }
        ArnLike      = { "AWS:SourceArn" = "arn:aws:cloudfront::123456789012:distribution/*" }
      }
    )
    error_message = "cloudfront.amazonaws.com may only kms:Decrypt (read-only OAC), for this account's distributions."
  }

  assert {
    condition     = length([for s in jsondecode(module.kms.key_policy).Statement : s if contains(["AllowS3", "AllowLogDelivery", "AllowLogDeliveryDataKeys"], try(s.Sid, ""))]) == 0
    error_message = "allow_cloudfront must not grant other services anything."
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
    condition     = one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowCloudWatchLogs"]).Principal.Service == "logs.us-east-1.amazonaws.com"
    error_message = "CloudWatch Logs is the regional logs principal."
  }

  assert {
    condition     = one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowCloudWatchLogs"]).Condition.ArnLike["kms:EncryptionContext:aws:logs:arn"] == "arn:aws:logs:us-east-1:123456789012:log-group:*"
    error_message = "CloudWatch Logs may use the key only for this account's log groups in this region."
  }

  # Bus and archive crypto is scoped by the event-bus encryption context, which
  # archive calls always carry (they carry no aws:SourceArn).
  assert {
    condition     = one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowEventBridge"]).Condition == { ArnLike = { "kms:EncryptionContext:aws:events:event-bus:arn" = "arn:aws:events:us-east-1:123456789012:event-bus/*" } }
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
      && one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowEventBridgeSNSTopics"]).Condition == { ArnLike = { "kms:EncryptionContext:aws:sns:topicArn" = "arn:aws:sns:us-east-1:123456789012:*" } }
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
        "arn:aws:events:us-east-1:123456789012:rule/*",
        "arn:aws:events:us-east-1:123456789012:event-bus/*",
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
        ArnLike      = { "kms:EncryptionContext:aws:sns:topicArn" = "arn:aws:sns:us-east-1:123456789012:*" }
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
        ArnLike      = { "aws:SourceArn" = "arn:aws:sns:us-east-1:123456789012:*" }
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
      && one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowCloudTrailEncryptLogs"]).Condition.ArnLike["aws:SourceArn"] == "arn:aws:cloudtrail:us-east-1:123456789012:trail/*"
    )
    error_message = "CloudTrail may only generate data keys for this account's trails (encryption context and aws:SourceArn)."
  }

  assert {
    condition = (
      one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowCloudTrailDescribeKey"]).Action == "kms:DescribeKey"
      && one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowCloudTrailDescribeKey"]).Condition == { ArnLike = { "aws:SourceArn" = "arn:aws:cloudtrail:us-east-1:123456789012:trail/*" } }
    )
    error_message = "CloudTrail DescribeKey is limited to this account's trails in this region."
  }

  # The trail bucket uses an S3 Bucket Key, which needs kms:Decrypt for the
  # CloudTrail principal.
  assert {
    condition = (
      one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowCloudTrailDecrypt"]).Action == "kms:Decrypt"
      && one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowCloudTrailDecrypt"]).Principal.Service == "cloudtrail.amazonaws.com"
      && one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowCloudTrailDecrypt"]).Condition == { ArnLike = { "aws:SourceArn" = "arn:aws:cloudtrail:us-east-1:123456789012:trail/*" } }
    )
    error_message = "CloudTrail may kms:Decrypt (S3 Bucket Key) only for this account's trails in this region (aws:SourceArn)."
  }

  assert {
    condition     = length([for s in jsondecode(module.kms.key_policy).Statement : s if contains(["AllowEventBridge", "AllowCloudWatchLogs", "AllowCloudWatchAlarmsSNSTopics"], try(s.Sid, ""))]) == 0
    error_message = "allow_cloudtrail must not grant other services anything."
  }
}

# --- #186: a replica must not copy the primary region's conditions ---

run "replica_policy_is_scoped_to_its_own_region_not_the_primarys" {
  command = plan

  variables {
    allow_cloudwatch_logs = true
    allow_autoscaling_ebs = true
    allow_backup          = true
    is_multi_region       = true
    replica_regions       = ["us-east-2"]
  }

  assert {
    condition = (
      one([
        for s in jsondecode(module.kms.replica_key_policies["us-east-2"]).Statement : s
        if try(s.Sid, "") == "AllowCloudWatchLogs"
      ]).Principal.Service == "logs.us-east-2.amazonaws.com"
      && one([
        for s in jsondecode(module.kms.replica_key_policies["us-east-2"]).Statement : s
        if try(s.Sid, "") == "AllowCloudWatchLogs"
      ]).Condition.ArnLike["kms:EncryptionContext:aws:logs:arn"] == "arn:aws:logs:us-east-2:123456789012:log-group:*"
    )
    error_message = "A replica's AllowCloudWatchLogs statement must name the replica's own region (us-east-2), not the primary's (us-east-1)."
  }

  assert {
    condition = (
      one([
        for s in jsondecode(module.kms.replica_key_policies["us-east-2"]).Statement : s
        if try(s.Sid, "") == "AllowAutoScalingEBSUsage"
      ]).Condition.StringEquals["kms:ViaService"] == "ec2.us-east-2.amazonaws.com"
    )
    error_message = "A replica's AllowAutoScalingEBSUsage statement's kms:ViaService must name the replica's own region."
  }

  assert {
    condition = (
      one([
        for s in jsondecode(module.kms.replica_key_policies["us-east-2"]).Statement : s
        if try(s.Sid, "") == "AllowBackupSNSTopics"
      ]).Condition.ArnLike["kms:EncryptionContext:aws:sns:topicArn"] == "arn:aws:sns:us-east-2:123456789012:*"
    )
    error_message = "A replica's AllowBackupSNSTopics statement's kms:EncryptionContext:aws:sns:topicArn must name the replica's own region (us-east-2), not the primary's (us-east-1)."
  }

  # The logs condition on the *primary's own* policy (module.kms.key_policy),
  # left untested until now, must still be scoped to the primary's region
  # once replicas exist alongside it.
  assert {
    condition = (
      one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowCloudWatchLogs"]).Principal.Service == "logs.us-east-1.amazonaws.com"
      && one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowCloudWatchLogs"]).Condition.ArnLike["kms:EncryptionContext:aws:logs:arn"] == "arn:aws:logs:us-east-1:123456789012:log-group:*"
    )
    error_message = "The primary key's own policy must stay scoped to the primary's region even when replicas exist."
  }
}

run "backup_publishes_to_sns_topics_only_for_this_accounts_topics" {
  command = plan

  variables {
    allow_backup = true
  }

  assert {
    condition = (
      one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowBackupSNSTopics"]).Principal.Service == "backup.amazonaws.com"
      && toset(one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowBackupSNSTopics"]).Action) == toset(["kms:GenerateDataKey*", "kms:Decrypt"])
      && one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowBackupSNSTopics"]).Condition == {
        StringEquals = { "aws:SourceAccount" = "123456789012" }
        ArnLike      = { "kms:EncryptionContext:aws:sns:topicArn" = "arn:aws:sns:us-east-1:123456789012:*" }
      }
    )
    error_message = "AWS Backup may use kms:GenerateDataKey*/kms:Decrypt only for this account's SNS topics in this region (aws:SourceAccount and the SNS encryption context)."
  }

  assert {
    condition     = length([for s in jsondecode(module.kms.key_policy).Statement : s if contains(["AllowEventBridge", "AllowCloudWatchLogs", "AllowCloudWatchAlarmsSNSTopics", "AllowSNS", "AllowS3", "AllowCloudTrailEncryptLogs"], try(s.Sid, ""))]) == 0
    error_message = "allow_backup must not grant other services anything."
  }
}

# key_administrators/key_users are a key-policy principal list: AWS KMS
# validates every principal named there at CreateKey/PutKeyPolicy time
# ("invalid principal" MalformedPolicyDocumentException for one that doesn't
# exist yet). A prod-shaped instance (no named key_administrators/key_users
# -- see stacks/orgs/fnx/prod/.../security.yaml's kms/main -- must not name
# any principal beyond the account root (enable_default_policy above), so
# the first real apply against a fresh account cannot fail that way. Real
# consumers instead get least-privilege access through their own IAM policy
# scoped to this key -- by ARN, or by alias when the consumer's own component
# plans/applies before kms/main (e.g. iam's ci_apply_kms_key_aliases) -- never
# through these lists -- the Cloud Posse pattern.
run "no_named_key_administrators_or_users_by_default" {
  command = plan

  assert {
    condition = length([
      for s in jsondecode(module.kms.key_policy).Statement : s
      if contains(["AllowKeyAdministration", "AllowKeyUsage", "AllowGrantsForAWSResources"], try(s.Sid, ""))
    ]) == 0
    error_message = "key_administrators/key_users default to [], so the key policy must name no principal beyond the account root."
  }
}

run "named_key_administrators_and_users_are_the_only_principals_granted" {
  command = plan

  variables {
    key_administrators = ["arn:aws:iam::123456789012:role/Admin"]
    key_users          = ["arn:aws:iam::123456789012:role/deploy"]
  }

  assert {
    condition = (
      one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowKeyAdministration"]).Principal.AWS == "arn:aws:iam::123456789012:role/Admin"
      && one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowKeyUsage"]).Principal.AWS == "arn:aws:iam::123456789012:role/deploy"
      && one([for s in jsondecode(module.kms.key_policy).Statement : s if try(s.Sid, "") == "AllowGrantsForAWSResources"]).Principal.AWS == "arn:aws:iam::123456789012:role/deploy"
    )
    error_message = "Named key_administrators/key_users must appear as the exact principal on their own statements, and only when explicitly set."
  }
}
