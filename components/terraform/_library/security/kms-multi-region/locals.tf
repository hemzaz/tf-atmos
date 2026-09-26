locals {
  use_custom_policy = var.key_policy != ""
  rotation_enabled  = var.enable_key_rotation && var.key_spec == "SYMMETRIC_DEFAULT"
  key_alias_name    = "alias/${coalesce(var.alias_name, var.name_prefix)}"

  common_tags = merge(
    var.tags,
    {
      ManagedBy = "Terraform"
      Module    = "kms-multi-region"
    }
  )

  # Every region a policy must be generated for: the primary key's region and
  # every replica's. A replica must not simply copy the primary's policy: the
  # region-specific statements below (CloudWatch Logs, EventBridge, SNS,
  # CloudTrail, the Auto Scaling EBS grant) embed the *primary's* region in
  # their ViaService conditions and resource ARNs if reused as-is, which scopes
  # a replica's grants to the wrong region entirely (#186).
  policy_source_regions = toset(concat([data.aws_region.current.region], var.replica_regions))

  default_policy_by_region = { for region, doc in data.aws_iam_policy_document.default : region => doc.json }
  default_policy           = local.default_policy_by_region[data.aws_region.current.region]
}

# One policy document per region in policy_source_regions (see above), each
# scoped to its own region rather than the primary's.
data "aws_iam_policy_document" "default" {
  for_each = local.policy_source_regions

  dynamic "statement" {
    for_each = var.enable_default_policy ? [1] : []

    content {
      sid       = "EnableRootAccountPermissions"
      actions   = ["kms:*"]
      resources = ["*"]

      principals {
        type        = "AWS"
        identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
      }
    }
  }

  dynamic "statement" {
    for_each = length(var.key_administrators) > 0 ? [1] : []

    content {
      sid = "AllowKeyAdministration"
      actions = [
        "kms:Create*",
        "kms:Describe*",
        "kms:Enable*",
        "kms:List*",
        "kms:Put*",
        "kms:Update*",
        "kms:Revoke*",
        "kms:Disable*",
        "kms:Get*",
        "kms:Delete*",
        "kms:TagResource",
        "kms:UntagResource",
        "kms:ScheduleKeyDeletion",
        "kms:CancelKeyDeletion",
        "kms:ReplicateKey",
        "kms:RotateKeyOnDemand",
      ]
      resources = ["*"]

      principals {
        type        = "AWS"
        identifiers = var.key_administrators
      }
    }
  }

  dynamic "statement" {
    for_each = length(var.key_users) > 0 ? [1] : []

    content {
      sid = "AllowKeyUsage"
      actions = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey",
      ]
      resources = ["*"]

      principals {
        type        = "AWS"
        identifiers = var.key_users
      }
    }
  }

  dynamic "statement" {
    for_each = length(var.key_users) > 0 ? [1] : []

    content {
      sid       = "AllowGrantsForAWSResources"
      actions   = ["kms:CreateGrant", "kms:ListGrants", "kms:RevokeGrant"]
      resources = ["*"]

      principals {
        type        = "AWS"
        identifiers = var.key_users
      }

      condition {
        test     = "Bool"
        variable = "kms:GrantIsForAWSResource"
        values   = ["true"]
      }
    }
  }

  dynamic "statement" {
    for_each = length(var.key_service_users) > 0 ? [1] : []

    content {
      sid = "AllowServiceUsage"
      actions = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey",
        "kms:CreateGrant",
      ]
      resources = ["*"]

      principals {
        type        = "Service"
        identifiers = var.key_service_users
      }
    }
  }

  # CloudWatch Logs, limited to this account's log groups in this region (the
  # pattern vpc/flow-logs.tf uses for its own key). Without it a log group
  # given this key fails to create: IAM delegation does not reach service
  # principals. each.key is this document's region (the primary's, or a
  # replica's), never the primary's region on a replica document.
  dynamic "statement" {
    for_each = var.allow_cloudwatch_logs ? [1] : []

    content {
      sid = "AllowCloudWatchLogs"
      actions = [
        "kms:Encrypt*",
        "kms:Decrypt*",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:Describe*",
      ]
      resources = ["*"]

      principals {
        type        = "Service"
        identifiers = ["logs.${each.key}.amazonaws.com"]
      }

      condition {
        test     = "ArnLike"
        variable = "kms:EncryptionContext:aws:logs:arn"
        values   = ["arn:${data.aws_partition.current.partition}:logs:${each.key}:${data.aws_caller_identity.current.account_id}:log-group:*"]
      }
    }
  }

  # The CloudWatch Logs delivery service (used for cross-account/cross-service
  # log shipping, e.g. a Step Functions state machine's execution history into
  # its own CMK-encrypted log group) authenticates as delivery.logs.amazonaws.com,
  # a distinct principal from logs.<region>.amazonaws.com above, and needs its
  # own kms:Decrypt statement, limited to this account (Step Functions docs,
  # "Encryption at rest", step 3). Region-independent: no per-region change.
  dynamic "statement" {
    for_each = var.allow_log_delivery ? [1] : []

    content {
      sid       = "AllowLogDelivery"
      actions   = ["kms:Decrypt"]
      resources = ["*"]

      principals {
        type        = "Service"
        identifiers = ["delivery.logs.amazonaws.com"]
      }

      condition {
        test     = "StringEquals"
        variable = "aws:SourceAccount"
        values   = [data.aws_caller_identity.current.account_id]
      }
    }
  }

  # EventBridge event buses and archives in this document's region. KMS calls
  # for a bus or an archive carry the encryption context
  # aws:events:event-bus:arn, which is always present; aws:SourceArn is not
  # sent for archive operations, so the crypto actions are scoped by context.
  dynamic "statement" {
    for_each = var.allow_eventbridge ? [1] : []

    content {
      sid = "AllowEventBridge"
      actions = [
        "kms:Decrypt",
        "kms:GenerateDataKey",
        "kms:ReEncrypt*",
      ]
      resources = ["*"]

      principals {
        type        = "Service"
        identifiers = ["events.amazonaws.com"]
      }

      condition {
        test     = "ArnLike"
        variable = "kms:EncryptionContext:aws:events:event-bus:arn"
        values   = ["arn:${data.aws_partition.current.partition}:events:${each.key}:${data.aws_caller_identity.current.account_id}:event-bus/*"]
      }
    }
  }

  # DescribeKey carries no encryption context, so it gets its own statement,
  # limited to this account (confused-deputy guard). Region-independent.
  dynamic "statement" {
    for_each = var.allow_eventbridge ? [1] : []

    content {
      sid       = "AllowEventBridgeDescribeKey"
      actions   = ["kms:DescribeKey"]
      resources = ["*"]

      principals {
        type        = "Service"
        identifiers = ["events.amazonaws.com"]
      }

      condition {
        test     = "StringEquals"
        variable = "aws:SourceAccount"
        values   = [data.aws_caller_identity.current.account_id]
      }
    }
  }

  # EventBridge rules publishing to an SNS topic encrypted with this key (for
  # example security-monitoring's alert topic). SNS binds the data key to the
  # topic with the encryption context aws:sns:topicArn, so the statement is
  # limited to this account's topics in this document's region. No
  # aws:SourceAccount / aws:SourceArn here: the SNS docs state those keys are
  # "not supported for EventBridge-to-encrypted topics" in a KMS policy, and
  # delivery fails with them. The topic policy carries the source conditions
  # instead.
  dynamic "statement" {
    for_each = var.allow_eventbridge ? [1] : []

    content {
      sid       = "AllowEventBridgeSNSTopics"
      actions   = ["kms:GenerateDataKey*", "kms:Decrypt"]
      resources = ["*"]

      principals {
        type        = "Service"
        identifiers = ["events.amazonaws.com"]
      }

      condition {
        test     = "ArnLike"
        variable = "kms:EncryptionContext:aws:sns:topicArn"
        values   = ["arn:${data.aws_partition.current.partition}:sns:${each.key}:${data.aws_caller_identity.current.account_id}:*"]
      }
    }
  }

  # EventBridge rules delivering to an SQS queue encrypted with this key (the
  # sqs component), and buses sending failed events to such a queue as their
  # dead-letter queue, which the bus/archive and SNS statements above do not
  # cover: SQS sends no bus or topic encryption context. Limited to this
  # account's rules and buses in this document's region. The SQS/EventBridge
  # docs place aws:SourceAccount and aws:SourceArn in this key policy; confirm
  # they are sent on the first real apply (delivery fails closed, to the
  # rule's DLQ or FailedInvocations, if not).
  dynamic "statement" {
    for_each = var.allow_eventbridge ? [1] : []

    content {
      sid       = "AllowEventBridgeSQSQueues"
      actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
      resources = ["*"]

      principals {
        type        = "Service"
        identifiers = ["events.amazonaws.com"]
      }

      condition {
        test     = "StringEquals"
        variable = "aws:SourceAccount"
        values   = [data.aws_caller_identity.current.account_id]
      }

      # rule/* for rule targets; event-bus/* for a bus dead-letter queue
      # (eventbridge event_bus_dlq_arn), whose sends carry the bus ARN.
      condition {
        test     = "ArnLike"
        variable = "aws:SourceArn"
        values = [
          "arn:${data.aws_partition.current.partition}:events:${each.key}:${data.aws_caller_identity.current.account_id}:rule/*",
          "arn:${data.aws_partition.current.partition}:events:${each.key}:${data.aws_caller_identity.current.account_id}:event-bus/*",
        ]
      }
    }
  }

  # CloudWatch alarms publishing to an SNS topic encrypted with this key:
  # scoped to this account's topics in this document's region by the same
  # encryption context, and to calls made for this account by
  # aws:SourceAccount (supported for CloudWatch, unlike EventBridge above).
  dynamic "statement" {
    for_each = var.allow_cloudwatch_alarms ? [1] : []

    content {
      sid       = "AllowCloudWatchAlarmsSNSTopics"
      actions   = ["kms:GenerateDataKey*", "kms:Decrypt"]
      resources = ["*"]

      principals {
        type        = "Service"
        identifiers = ["cloudwatch.amazonaws.com"]
      }

      condition {
        test     = "StringEquals"
        variable = "aws:SourceAccount"
        values   = [data.aws_caller_identity.current.account_id]
      }

      condition {
        test     = "ArnLike"
        variable = "kms:EncryptionContext:aws:sns:topicArn"
        values   = ["arn:${data.aws_partition.current.partition}:sns:${each.key}:${data.aws_caller_identity.current.account_id}:*"]
      }
    }
  }

  # CloudTrail trails of this account (the cloudtrail component) encrypting
  # their log files with this key. GenerateDataKey* is bound to the trail by
  # the encryption context aws:cloudtrail:arn (region wildcarded, as trail
  # ARNs from the API carry no region); every statement is limited to this
  # document's region's trails by aws:SourceArn (confused-deputy guard).
  # Principals reading the logs back get kms:Decrypt through IAM (the root
  # statement).
  dynamic "statement" {
    for_each = var.allow_cloudtrail ? [1] : []

    content {
      sid       = "AllowCloudTrailEncryptLogs"
      actions   = ["kms:GenerateDataKey*"]
      resources = ["*"]

      principals {
        type        = "Service"
        identifiers = ["cloudtrail.amazonaws.com"]
      }

      condition {
        test     = "StringLike"
        variable = "kms:EncryptionContext:aws:cloudtrail:arn"
        values   = ["arn:${data.aws_partition.current.partition}:cloudtrail:*:${data.aws_caller_identity.current.account_id}:trail/*"]
      }

      condition {
        test     = "ArnLike"
        variable = "aws:SourceArn"
        values   = ["arn:${data.aws_partition.current.partition}:cloudtrail:${each.key}:${data.aws_caller_identity.current.account_id}:trail/*"]
      }
    }
  }

  # The trail's S3 bucket uses an S3 Bucket Key, which needs kms:Decrypt for
  # the CloudTrail principal.
  dynamic "statement" {
    for_each = var.allow_cloudtrail ? [1] : []

    content {
      sid       = "AllowCloudTrailDecrypt"
      actions   = ["kms:Decrypt"]
      resources = ["*"]

      principals {
        type        = "Service"
        identifiers = ["cloudtrail.amazonaws.com"]
      }

      condition {
        test     = "ArnLike"
        variable = "aws:SourceArn"
        values   = ["arn:${data.aws_partition.current.partition}:cloudtrail:${each.key}:${data.aws_caller_identity.current.account_id}:trail/*"]
      }
    }
  }

  dynamic "statement" {
    for_each = var.allow_cloudtrail ? [1] : []

    content {
      sid       = "AllowCloudTrailDescribeKey"
      actions   = ["kms:DescribeKey"]
      resources = ["*"]

      principals {
        type        = "Service"
        identifiers = ["cloudtrail.amazonaws.com"]
      }

      condition {
        test     = "ArnLike"
        variable = "aws:SourceArn"
        values   = ["arn:${data.aws_partition.current.partition}:cloudtrail:${each.key}:${data.aws_caller_identity.current.account_id}:trail/*"]
      }
    }
  }

  # SNS delivering to SQS queues encrypted with this key (an sns subscription
  # to an sqs queue), limited to this account's topics in this document's
  # region.
  dynamic "statement" {
    for_each = var.allow_sns ? [1] : []

    content {
      sid       = "AllowSNS"
      actions   = ["kms:Decrypt", "kms:GenerateDataKey*"]
      resources = ["*"]

      principals {
        type        = "Service"
        identifiers = ["sns.amazonaws.com"]
      }

      condition {
        test     = "StringEquals"
        variable = "aws:SourceAccount"
        values   = [data.aws_caller_identity.current.account_id]
      }

      condition {
        test     = "ArnLike"
        variable = "aws:SourceArn"
        values   = ["arn:${data.aws_partition.current.partition}:sns:${each.key}:${data.aws_caller_identity.current.account_id}:*"]
      }
    }
  }
  # S3 event notifications to SQS queues / SNS topics encrypted with this key,
  # limited to this account's buckets (bucket ARNs carry no account or
  # region, so aws:SourceAccount does the pinning; aws:SourceArn keeps it to
  # buckets). Region-independent.
  dynamic "statement" {
    for_each = var.allow_s3 ? [1] : []

    content {
      sid       = "AllowS3"
      actions   = ["kms:Decrypt", "kms:GenerateDataKey*"]
      resources = ["*"]

      principals {
        type        = "Service"
        identifiers = ["s3.amazonaws.com"]
      }

      condition {
        test     = "StringEquals"
        variable = "aws:SourceAccount"
        values   = [data.aws_caller_identity.current.account_id]
      }

      condition {
        test     = "ArnLike"
        variable = "aws:SourceArn"
        values   = ["arn:${data.aws_partition.current.partition}:s3:::*"]
      }
    }
  }

  # The EC2 Auto Scaling service-linked role that every managed node group /
  # ASG uses to launch instances needs kms:CreateGrant (scoped to
  # kms:GrantIsForAWSResource, AWS's documented pattern for EBS + Auto
  # Scaling) plus the crypto actions used through that grant, or new instances
  # on a CMK-encrypted launch template fail to launch. The role
  # (aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling)
  # is a service-linked role AWS creates the first time an account uses Auto
  # Scaling, not something Terraform manages here; the key policy may name it
  # even though nothing in this module creates it. kms:ViaService is scoped to
  # this document's region: EC2 calls KMS through ec2.<region>.amazonaws.com,
  # so a replica's statement must name the replica's own region, not the
  # primary's.
  dynamic "statement" {
    for_each = var.allow_autoscaling_ebs ? [1] : []

    content {
      sid = "AllowAutoScalingEBSUsage"
      actions = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey",
      ]
      resources = ["*"]

      principals {
        type        = "AWS"
        identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"]
      }

      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = ["ec2.${each.key}.amazonaws.com"]
      }

      condition {
        test     = "StringEquals"
        variable = "kms:CallerAccount"
        values   = [data.aws_caller_identity.current.account_id]
      }
    }
  }

  dynamic "statement" {
    for_each = var.allow_autoscaling_ebs ? [1] : []

    content {
      sid       = "AllowAutoScalingEBSGrant"
      actions   = ["kms:CreateGrant"]
      resources = ["*"]

      principals {
        type        = "AWS"
        identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"]
      }

      condition {
        test     = "Bool"
        variable = "kms:GrantIsForAWSResource"
        values   = ["true"]
      }
    }
  }
}
