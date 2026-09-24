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

  default_policy = data.aws_iam_policy_document.default.json
}

data "aws_iam_policy_document" "default" {
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
  # principals.
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
        identifiers = ["logs.${data.aws_region.current.region}.amazonaws.com"]
      }

      condition {
        test     = "ArnLike"
        variable = "kms:EncryptionContext:aws:logs:arn"
        values   = ["arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:*"]
      }
    }
  }

  # EventBridge event buses and archives in this account and region. KMS calls
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
        values   = ["arn:${data.aws_partition.current.partition}:events:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:event-bus/*"]
      }
    }
  }

  # DescribeKey carries no encryption context, so it gets its own statement,
  # limited to this account (confused-deputy guard).
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
  # limited to this account's topics in this region. No aws:SourceAccount /
  # aws:SourceArn here: the SNS docs state those keys are "not supported for
  # EventBridge-to-encrypted topics" in a KMS policy, and delivery fails with
  # them. The topic policy carries the source conditions instead.
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
        values   = ["arn:${data.aws_partition.current.partition}:sns:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:*"]
      }
    }
  }

  # CloudWatch alarms publishing to an SNS topic encrypted with this key:
  # scoped to this account's topics by the same encryption context, and to
  # calls made for this account by aws:SourceAccount (supported for
  # CloudWatch, unlike EventBridge above).
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
        values   = ["arn:${data.aws_partition.current.partition}:sns:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:*"]
      }
    }
  }

  # CloudTrail trails of this account (the cloudtrail component) encrypting
  # their log files with this key. GenerateDataKey* is bound to the trail by
  # the encryption context aws:cloudtrail:arn; both statements are limited to
  # this account's trails by aws:SourceArn (confused-deputy guard). Reading the
  # logs back needs kms:Decrypt, which IAM grants through the root statement.
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
        values   = ["arn:${data.aws_partition.current.partition}:cloudtrail:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:trail/*"]
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
        values   = ["arn:${data.aws_partition.current.partition}:cloudtrail:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:trail/*"]
      }
    }
  }
}
