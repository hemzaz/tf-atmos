locals {
  name_prefix = "${var.name_prefix}-${var.environment}"

  common_tags = merge(
    {
      Name        = "${local.name_prefix}-backup-vault"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Module      = "backup-vault"
    },
    var.tags
  )
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

#------------------------------------------------------------------------------
# KMS Key for Backup Vault Encryption
#------------------------------------------------------------------------------
resource "aws_kms_key" "backup" {
  count = var.kms_key_id == null ? 1 : 0

  description             = "KMS key for AWS Backup ${local.name_prefix}"
  deletion_window_in_days = var.kms_deletion_window_days
  enable_key_rotation     = true

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-backup-kms"
    }
  )
}

resource "aws_kms_alias" "backup" {
  count = var.kms_key_id == null ? 1 : 0

  name          = "alias/${local.name_prefix}-backup"
  target_key_id = aws_kms_key.backup[0].key_id
}

#------------------------------------------------------------------------------
# SNS Topic for Backup Notifications
#------------------------------------------------------------------------------
resource "aws_sns_topic" "backup_notifications" {
  count = var.enable_notifications ? 1 : 0

  name              = "${local.name_prefix}-backup-notifications"
  kms_master_key_id = var.kms_key_id != null ? var.kms_key_id : aws_kms_key.backup[0].id

  tags = local.common_tags
}

resource "aws_sns_topic_subscription" "backup_notifications" {
  for_each = var.enable_notifications ? toset(var.notification_endpoints) : []

  topic_arn = aws_sns_topic.backup_notifications[0].arn
  protocol  = "email"
  endpoint  = each.value
}

#------------------------------------------------------------------------------
# AWS Backup Vault
#------------------------------------------------------------------------------
resource "aws_backup_vault" "this" {
  name        = "${local.name_prefix}-vault"
  kms_key_arn = var.kms_key_id != null ? var.kms_key_id : aws_kms_key.backup[0].arn

  tags = local.common_tags
}

resource "aws_backup_vault_lock_configuration" "this" {
  count = var.enable_vault_lock ? 1 : 0

  backup_vault_name   = aws_backup_vault.this.name
  changeable_for_days = var.vault_lock_changeable_days
  max_retention_days  = var.vault_lock_max_retention_days
  min_retention_days  = var.vault_lock_min_retention_days
}

resource "aws_backup_vault_notifications" "this" {
  count = var.enable_notifications ? 1 : 0

  backup_vault_name   = aws_backup_vault.this.name
  sns_topic_arn       = aws_sns_topic.backup_notifications[0].arn
  backup_vault_events = var.notification_events
}

resource "aws_backup_vault_policy" "this" {
  count = var.vault_policy != null ? 1 : 0

  backup_vault_name = aws_backup_vault.this.name
  policy            = var.vault_policy
}

#------------------------------------------------------------------------------
# IAM Role for AWS Backup
#------------------------------------------------------------------------------
resource "aws_iam_role" "backup" {
  name               = "${local.name_prefix}-backup-role"
  assume_role_policy = data.aws_iam_policy_document.backup_assume_role.json

  tags = local.common_tags
}

data "aws_iam_policy_document" "backup_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["backup.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role_policy_attachment" "backup" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_iam_role_policy_attachment" "restore" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

#------------------------------------------------------------------------------
# AWS Backup Plans
#------------------------------------------------------------------------------
resource "aws_backup_plan" "this" {
  for_each = var.backup_plans

  name = "${local.name_prefix}-${each.key}"

  dynamic "rule" {
    for_each = each.value.rules

    content {
      rule_name         = rule.value.name
      target_vault_name = aws_backup_vault.this.name
      schedule          = rule.value.schedule
      start_window      = lookup(rule.value, "start_window", 60)
      completion_window = lookup(rule.value, "completion_window", 120)
      enable_continuous_backup = lookup(rule.value, "enable_continuous_backup", false)

      lifecycle {
        delete_after       = lookup(rule.value.lifecycle, "delete_after", null)
        cold_storage_after = lookup(rule.value.lifecycle, "cold_storage_after", null)
      }

      dynamic "copy_action" {
        for_each = lookup(rule.value, "copy_actions", [])

        content {
          destination_vault_arn = copy_action.value.destination_vault_arn

          lifecycle {
            delete_after       = lookup(copy_action.value.lifecycle, "delete_after", null)
            cold_storage_after = lookup(copy_action.value.lifecycle, "cold_storage_after", null)
          }
        }
      }

      recovery_point_tags = merge(
        local.common_tags,
        lookup(rule.value, "recovery_point_tags", {})
      )
    }
  }

  dynamic "advanced_backup_setting" {
    for_each = lookup(each.value, "advanced_backup_settings", [])

    content {
      backup_options = advanced_backup_setting.value.backup_options
      resource_type  = advanced_backup_setting.value.resource_type
    }
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-${each.key}"
    }
  )
}

#------------------------------------------------------------------------------
# AWS Backup Selection
#------------------------------------------------------------------------------
resource "aws_backup_selection" "this" {
  for_each = var.backup_plans

  name         = "${local.name_prefix}-${each.key}-selection"
  plan_id      = aws_backup_plan.this[each.key].id
  iam_role_arn = aws_iam_role.backup.arn

  dynamic "selection_tag" {
    for_each = lookup(each.value, "selection_tags", [])

    content {
      type  = "STRINGEQUALS"
      key   = selection_tag.value.key
      value = selection_tag.value.value
    }
  }

  resources = lookup(each.value, "resource_arns", [])

  dynamic "condition" {
    for_each = lookup(each.value, "conditions", [])

    content {
      dynamic "string_equals" {
        for_each = lookup(condition.value, "string_equals", [])

        content {
          key   = string_equals.value.key
          value = string_equals.value.value
        }
      }

      dynamic "string_like" {
        for_each = lookup(condition.value, "string_like", [])

        content {
          key   = string_like.value.key
          value = string_like.value.value
        }
      }

      dynamic "string_not_equals" {
        for_each = lookup(condition.value, "string_not_equals", [])

        content {
          key   = string_not_equals.value.key
          value = string_not_equals.value.value
        }
      }

      dynamic "string_not_like" {
        for_each = lookup(condition.value, "string_not_like", [])

        content {
          key   = string_not_like.value.key
          value = string_not_like.value.value
        }
      }
    }
  }
}

#------------------------------------------------------------------------------
# CloudWatch Alarms
#------------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "backup_job_failed" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.name_prefix}-backup-job-failed"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "NumberOfBackupJobsFailed"
  namespace           = "AWS/Backup"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "AWS Backup job failed"
  treat_missing_data  = "notBreaching"

  alarm_actions = var.alarm_actions

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "restore_job_failed" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.name_prefix}-restore-job-failed"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "NumberOfRestoreJobsFailed"
  namespace           = "AWS/Backup"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "AWS Backup restore job failed"
  treat_missing_data  = "notBreaching"

  alarm_actions = var.alarm_actions

  tags = local.common_tags
}
