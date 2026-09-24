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

  # EventBridge event buses and archives, limited to this account and region
  # (aws:SourceAccount / aws:SourceArn guard against the confused deputy).
  dynamic "statement" {
    for_each = var.allow_eventbridge ? [1] : []

    content {
      sid = "AllowEventBridge"
      actions = [
        "kms:Decrypt",
        "kms:GenerateDataKey",
        "kms:ReEncrypt*",
        "kms:DescribeKey",
      ]
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

      condition {
        test     = "ArnLike"
        variable = "aws:SourceArn"
        values = [
          "arn:${data.aws_partition.current.partition}:events:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:event-bus/*",
          "arn:${data.aws_partition.current.partition}:events:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:archive/*",
        ]
      }
    }
  }
}
