locals {
  audit_access_enabled = module.this.enabled && var.audit_access_enabled
  audit_account_id     = module.account_map.outputs.full_account_map[module.account_map.outputs.audit_account_account_name]

  kms_key_alias    = var.kms_key_alias != null ? var.kms_key_alias : format("alias/%s", module.this.id)
  kms_abac_enabled = length(var.kms_abac_statements) > 0
}

module "kms_key_cloudtrail" {
  source  = "cloudposse/kms-key/aws"
  version = "0.12.2"

  description             = "KMS key for CloudTrail"
  deletion_window_in_days = 10
  enable_key_rotation     = true
  policy                  = join("", data.aws_iam_policy_document.kms_key_cloudtrail[*].json)

  context = module.this.context
}

data "aws_caller_identity" "this" {
  count = local.enabled ? 1 : 0
}

data "aws_partition" "current" {
  count = local.enabled ? 1 : 0
}

data "aws_iam_policy_document" "kms_key_cloudtrail" {
  count = local.enabled ? 1 : 0

  statement {
    sid    = "Allow the account identity to manage the KMS key"
    effect = "Allow"

    actions = [
      "kms:*"
    ]

    resources = [
      "*"
    ]

    principals {
      type = "AWS"
      identifiers = [
        format("arn:${join("", data.aws_partition.current[*].partition)}:iam::%s:root", join("", data.aws_caller_identity.this[*].account_id))
      ]
    }
  }

  statement {
    sid    = "Allow CloudTrail to encrypt with the KMS key"
    effect = "Allow"

    actions = [
      "kms:Encrypt",
      "kms:GenerateDataKey*",
      "kms:DescribeKey"
    ]

    resources = [
      "*"
    ]

    principals {
      type = "Service"
      identifiers = [
        "cloudtrail.amazonaws.com"
      ]
    }
    condition {
      test     = "StringLike"
      variable = "kms:EncryptionContext:aws:cloudtrail:arn"
      values = [
        format("arn:${join("", data.aws_partition.current[*].partition)}:cloudtrail:*:%s:trail/*", join("", data.aws_caller_identity.this[*].account_id))
      ]
    }
  }

  dynamic "statement" {
    for_each = var.kms_key_enabled ? [1] : []
    content {
      sid    = "Allow CloudWatch Logs to encrypt with the KMS key"
      effect = "Allow"

      actions = [
        "kms:Encrypt*",
        "kms:Decrypt*",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:Describe*"
      ]

      resources = [
        "*"
      ]

      principals {
        type = "Service"
        identifiers = [
          format("logs.%s.amazonaws.com", var.region)
        ]
      }

      condition {
        test     = "ArnLike"
        variable = "kms:EncryptionContext:aws:logs:arn"
        values = [
          format("arn:${join("", data.aws_partition.current[*].partition)}:logs:${var.region}:%s:log-group:*", join("", data.aws_caller_identity.this[*].account_id))
        ]
      }
    }
  }

  dynamic "statement" {
    for_each = local.audit_access_enabled ? [1] : []
    content {
      sid    = "Allow Audit to decrypt with the KMS key"
      effect = "Allow"

      actions = [
        "kms:Decrypt",
        "kms:DescribeKey"
      ]

      resources = [
        "*"
      ]

      principals {
        type = "AWS"
        identifiers = [
          format("arn:${join("", data.aws_partition.current[*].partition)}:iam::%s:root", local.audit_account_id)
        ]
      }
      condition {
        test     = "StringLike"
        variable = "kms:EncryptionContext:aws:cloudtrail:arn"
        values = [
          format("arn:${join("", data.aws_partition.current[*].partition)}:cloudtrail:*:%s:trail/*", join("", data.aws_caller_identity.this[*].account_id))
        ]
      }
    }
  }

  dynamic "statement" {
    for_each = var.kms_key_enabled && local.kms_abac_enabled ? var.kms_abac_statements : []
    content {
      sid       = lookup(statement.value, "sid", null)
      effect    = statement.value.effect
      actions   = statement.value.actions
      resources = ["*"]

      condition {
        test     = "ForAnyValue:StringLike"
        variable = "kms:ResourceAliases"
        values = [
          local.kms_key_alias
        ]
      }

      dynamic "condition" {
        for_each = statement.value.conditions
        content {
          test     = condition.value.test
          variable = condition.value.variable
          values   = condition.value.values
        }
      }
    }
  }
}
