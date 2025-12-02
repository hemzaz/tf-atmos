# AWS Backup for DynamoDB State Lock Table
# Provides automated backup and disaster recovery capabilities

# Backup vault for DynamoDB table backups
resource "aws_backup_vault" "dynamodb" {
  count = var.enable_backup_vault ? 1 : 0

  name        = "${var.dynamodb_table_name}-backup-vault"
  kms_key_arn = aws_kms_key.terraform_state_key.arn

  tags = merge(
    var.tags,
    {
      Name        = "${var.dynamodb_table_name}-backup-vault"
      Purpose     = "terraform-state-backup"
      Environment = var.environment
    }
  )
}

# Backup vault policy for access control
resource "aws_backup_vault_policy" "dynamodb" {
  count = var.enable_backup_vault ? 1 : 0

  backup_vault_name = aws_backup_vault.dynamodb[0].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyDeleteBackup"
        Effect = "Deny"
        Principal = {
          AWS = "*"
        }
        Action = [
          "backup:DeleteBackupVault",
          "backup:DeleteRecoveryPoint",
          "backup:PutBackupVaultAccessPolicy",
          "backup:DeleteBackupVaultAccessPolicy",
          "backup:PutBackupVaultNotifications",
          "backup:DeleteBackupVaultNotifications"
        ]
        Resource = aws_backup_vault.dynamodb[0].arn
      }
    ]
  })
}

# IAM role for AWS Backup
resource "aws_iam_role" "backup" {
  count = var.enable_backup_vault ? 1 : 0

  name = "${var.dynamodb_table_name}-backup-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "backup.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name    = "${var.dynamodb_table_name}-backup-role"
      Purpose = "aws-backup-service-role"
    }
  )
}

# Attach AWS managed policy for DynamoDB backup
resource "aws_iam_role_policy_attachment" "backup_dynamodb" {
  count = var.enable_backup_vault ? 1 : 0

  role       = aws_iam_role.backup[0].name
  policy_arn = "arn:aws:iam::aws:policy/AWSBackupServiceRolePolicyForBackup"
}

# Additional policy for restore operations
resource "aws_iam_role_policy_attachment" "backup_restore" {
  count = var.enable_backup_vault ? 1 : 0

  role       = aws_iam_role.backup[0].name
  policy_arn = "arn:aws:iam::aws:policy/AWSBackupServiceRolePolicyForRestores"
}

# Backup plan with multiple schedules
resource "aws_backup_plan" "dynamodb" {
  count = var.enable_backup_vault ? 1 : 0

  name = "${var.dynamodb_table_name}-backup-plan"

  # Daily backups with 30-day retention
  rule {
    rule_name         = "daily_backup"
    target_vault_name = aws_backup_vault.dynamodb[0].name
    schedule          = var.backup_schedule_daily
    start_window      = 60  # Minutes
    completion_window = 120 # Minutes

    lifecycle {
      delete_after       = var.backup_retention_days_daily
      cold_storage_after = var.backup_cold_storage_after_days
    }

    recovery_point_tags = merge(
      var.tags,
      {
        BackupType = "daily"
        Automated  = "true"
      }
    )
  }

  # Weekly backups with longer retention (for production)
  dynamic "rule" {
    for_each = var.environment == "prod" && var.enable_weekly_backups ? [1] : []
    content {
      rule_name         = "weekly_backup"
      target_vault_name = aws_backup_vault.dynamodb[0].name
      schedule          = var.backup_schedule_weekly
      start_window      = 60
      completion_window = 120

      lifecycle {
        delete_after       = var.backup_retention_days_weekly
        cold_storage_after = var.backup_cold_storage_after_days_weekly
      }

      recovery_point_tags = merge(
        var.tags,
        {
          BackupType = "weekly"
          Automated  = "true"
        }
      )
    }
  }

  # Monthly backups with longest retention (for production)
  dynamic "rule" {
    for_each = var.environment == "prod" && var.enable_monthly_backups ? [1] : []
    content {
      rule_name         = "monthly_backup"
      target_vault_name = aws_backup_vault.dynamodb[0].name
      schedule          = var.backup_schedule_monthly
      start_window      = 60
      completion_window = 120

      lifecycle {
        delete_after       = var.backup_retention_days_monthly
        cold_storage_after = var.backup_cold_storage_after_days_monthly
      }

      recovery_point_tags = merge(
        var.tags,
        {
          BackupType = "monthly"
          Automated  = "true"
        }
      )
    }
  }

  tags = merge(
    var.tags,
    {
      Name        = "${var.dynamodb_table_name}-backup-plan"
      Purpose     = "automated-backup-schedule"
      Environment = var.environment
    }
  )
}

# Backup selection - which resources to backup
resource "aws_backup_selection" "dynamodb" {
  count = var.enable_backup_vault ? 1 : 0

  name         = "${var.dynamodb_table_name}-backup-selection"
  iam_role_arn = aws_iam_role.backup[0].arn
  plan_id      = aws_backup_plan.dynamodb[0].id

  resources = [
    aws_dynamodb_table.terraform_locks.arn
  ]

  selection_tag {
    type  = "STRINGEQUALS"
    key   = "BackupRequired"
    value = "true"
  }
}

# CloudWatch alarm for backup failures
resource "aws_cloudwatch_metric_alarm" "backup_failed" {
  count = var.enable_backup_vault && var.enable_backup_alarms ? 1 : 0

  alarm_name          = "${var.dynamodb_table_name}-backup-failed"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "NumberOfBackupJobsFailed"
  namespace           = "AWS/Backup"
  period              = "3600"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "Alert when DynamoDB backup jobs fail"
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.backup_alarm_actions

  dimensions = {
    BackupVaultName = aws_backup_vault.dynamodb[0].name
  }

  tags = var.tags
}

# CloudWatch alarm for backup job completion
resource "aws_cloudwatch_metric_alarm" "backup_completion" {
  count = var.enable_backup_vault && var.enable_backup_alarms ? 1 : 0

  alarm_name          = "${var.dynamodb_table_name}-backup-no-completion"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "NumberOfBackupJobsCompleted"
  namespace           = "AWS/Backup"
  period              = "86400" # 24 hours
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "Alert when no backup jobs complete in 24 hours"
  treat_missing_data  = "breaching"
  alarm_actions       = var.backup_alarm_actions

  dimensions = {
    BackupVaultName = aws_backup_vault.dynamodb[0].name
  }

  tags = var.tags
}

# EventBridge rule for backup notifications
resource "aws_cloudwatch_event_rule" "backup_events" {
  count = var.enable_backup_vault && var.enable_backup_events ? 1 : 0

  name        = "${var.dynamodb_table_name}-backup-events"
  description = "Capture AWS Backup events for DynamoDB table"

  event_pattern = jsonencode({
    source      = ["aws.backup"]
    detail-type = ["Backup Job State Change"]
    detail = {
      backupVaultName = [aws_backup_vault.dynamodb[0].name]
    }
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "backup_events" {
  count = var.enable_backup_vault && var.enable_backup_events && length(var.backup_event_sns_topics) > 0 ? 1 : 0

  rule      = aws_cloudwatch_event_rule.backup_events[0].name
  target_id = "SendToSNS"
  arn       = var.backup_event_sns_topics[0]
}

# DynamoDB table lifecycle policy for on-demand backups
resource "aws_dynamodb_table_item" "backup_lifecycle" {
  count = var.enable_backup_vault && var.enable_backup_lifecycle_tags ? 1 : 0

  table_name = aws_dynamodb_table.terraform_locks.name
  hash_key   = aws_dynamodb_table.terraform_locks.hash_key

  # This is a metadata item to track backup lifecycle
  item = jsonencode({
    LockID = { S = "_backup_lifecycle_metadata" }
    BackupPolicy = {
      M = {
        Enabled = { BOOL = true }
        LastBackup = {
          S = timestamp()
        }
        RetentionDays = {
          N = tostring(var.backup_retention_days_daily)
        }
      }
    }
  })

  lifecycle {
    ignore_changes = [item]
  }
}
