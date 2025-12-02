locals {
  name_prefix = "${var.tags["Environment"]}-${var.tags["Name"] != null ? var.tags["Name"] : "backup"}"
}

# AWS Backup Vault
resource "aws_backup_vault" "main" {
  name        = local.name_prefix
  kms_key_arn = var.kms_key_arn

  tags = merge(
    var.tags,
    {
      Name = local.name_prefix
    }
  )
}

# Cross-Region Backup Vault (if enabled)
resource "aws_backup_vault" "cross_region" {
  count    = var.enable_cross_region_backup ? 1 : 0
  provider = aws.replica

  name        = "${local.name_prefix}-replica"
  kms_key_arn = var.replica_kms_key_arn

  tags = merge(
    var.tags,
    {
      Name = "${local.name_prefix}-replica"
    }
  )
}

# Backup Vault Lock (compliance mode)
resource "aws_backup_vault_lock_configuration" "main" {
  count = var.enable_vault_lock ? 1 : 0

  backup_vault_name   = aws_backup_vault.main.name
  changeable_for_days = var.vault_lock_changeable_days
  min_retention_days  = var.vault_lock_min_retention_days
  max_retention_days  = var.vault_lock_max_retention_days
}

# IAM Role for AWS Backup
resource "aws_iam_role" "backup" {
  name = "${local.name_prefix}-service-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "backup.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "backup" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_iam_role_policy_attachment" "restore" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

# Daily Backup Plan
resource "aws_backup_plan" "daily" {
  name = "${local.name_prefix}-daily"

  rule {
    rule_name         = "daily-backup"
    target_vault_name = aws_backup_vault.main.name
    schedule          = var.daily_backup_schedule
    start_window      = var.backup_start_window
    completion_window = var.backup_completion_window

    lifecycle {
      delete_after                = var.daily_retention_days
      cold_storage_after          = var.daily_cold_storage_days
      opt_in_to_archive_for_supported_resources = var.enable_archive_tier
    }

    copy_action {
      destination_vault_arn = var.enable_cross_region_backup ? aws_backup_vault.cross_region[0].arn : null

      lifecycle {
        delete_after       = var.daily_retention_days
        cold_storage_after = var.daily_cold_storage_days
      }
    }

    recovery_point_tags = merge(
      var.tags,
      {
        BackupType = "Daily"
      }
    )
  }

  advanced_backup_setting {
    backup_options = {
      WindowsVSS = "enabled"
    }
    resource_type = "EC2"
  }

  tags = var.tags
}

# Weekly Backup Plan
resource "aws_backup_plan" "weekly" {
  name = "${local.name_prefix}-weekly"

  rule {
    rule_name         = "weekly-backup"
    target_vault_name = aws_backup_vault.main.name
    schedule          = var.weekly_backup_schedule
    start_window      = var.backup_start_window
    completion_window = var.backup_completion_window

    lifecycle {
      delete_after                = var.weekly_retention_days
      cold_storage_after          = var.weekly_cold_storage_days
      opt_in_to_archive_for_supported_resources = var.enable_archive_tier
    }

    copy_action {
      destination_vault_arn = var.enable_cross_region_backup ? aws_backup_vault.cross_region[0].arn : null

      lifecycle {
        delete_after       = var.weekly_retention_days
        cold_storage_after = var.weekly_cold_storage_days
      }
    }

    recovery_point_tags = merge(
      var.tags,
      {
        BackupType = "Weekly"
      }
    )
  }

  tags = var.tags
}

# Monthly Backup Plan
resource "aws_backup_plan" "monthly" {
  name = "${local.name_prefix}-monthly"

  rule {
    rule_name         = "monthly-backup"
    target_vault_name = aws_backup_vault.main.name
    schedule          = var.monthly_backup_schedule
    start_window      = var.backup_start_window
    completion_window = var.backup_completion_window

    lifecycle {
      delete_after                = var.monthly_retention_days
      cold_storage_after          = var.monthly_cold_storage_days
      opt_in_to_archive_for_supported_resources = var.enable_archive_tier
    }

    copy_action {
      destination_vault_arn = var.enable_cross_region_backup ? aws_backup_vault.cross_region[0].arn : null

      lifecycle {
        delete_after       = var.monthly_retention_days
        cold_storage_after = var.monthly_cold_storage_days
      }
    }

    recovery_point_tags = merge(
      var.tags,
      {
        BackupType = "Monthly"
      }
    )
  }

  tags = var.tags
}

# Backup Selection for RDS
resource "aws_backup_selection" "rds_daily" {
  count = length(var.rds_instances) > 0 ? 1 : 0

  name         = "${local.name_prefix}-rds-daily"
  plan_id      = aws_backup_plan.daily.id
  iam_role_arn = aws_iam_role.backup.arn

  resources = [for instance in var.rds_instances : "arn:aws:rds:${var.region}:${data.aws_caller_identity.current.account_id}:db:${instance}"]
}

# Backup Selection for DynamoDB
resource "aws_backup_selection" "dynamodb_daily" {
  count = length(var.dynamodb_tables) > 0 ? 1 : 0

  name         = "${local.name_prefix}-dynamodb-daily"
  plan_id      = aws_backup_plan.daily.id
  iam_role_arn = aws_iam_role.backup.arn

  resources = [for table in var.dynamodb_tables : "arn:aws:dynamodb:${var.region}:${data.aws_caller_identity.current.account_id}:table/${table}"]
}

# Backup Selection for EFS
resource "aws_backup_selection" "efs_daily" {
  count = length(var.efs_file_systems) > 0 ? 1 : 0

  name         = "${local.name_prefix}-efs-daily"
  plan_id      = aws_backup_plan.daily.id
  iam_role_arn = aws_iam_role.backup.arn

  resources = [for fs in var.efs_file_systems : "arn:aws:elasticfilesystem:${var.region}:${data.aws_caller_identity.current.account_id}:file-system/${fs}"]
}

# Backup Selection for EC2 (by tags)
resource "aws_backup_selection" "ec2_daily" {
  count = var.enable_ec2_backup ? 1 : 0

  name         = "${local.name_prefix}-ec2-daily"
  plan_id      = aws_backup_plan.daily.id
  iam_role_arn = aws_iam_role.backup.arn

  selection_tag {
    type  = "STRINGEQUALS"
    key   = "Backup"
    value = "true"
  }

  selection_tag {
    type  = "STRINGEQUALS"
    key   = "Environment"
    value = var.tags["Environment"]
  }
}

# Backup Selection for EBS Volumes
resource "aws_backup_selection" "ebs_daily" {
  count = var.enable_ebs_backup ? 1 : 0

  name         = "${local.name_prefix}-ebs-daily"
  plan_id      = aws_backup_plan.daily.id
  iam_role_arn = aws_iam_role.backup.arn

  selection_tag {
    type  = "STRINGEQUALS"
    key   = "Backup"
    value = "true"
  }

  resources = var.ebs_volume_ids != null ? [for vol in var.ebs_volume_ids : "arn:aws:ec2:${var.region}:${data.aws_caller_identity.current.account_id}:volume/${vol}"] : []
}

# Backup Notifications
resource "aws_sns_topic" "backup_notifications" {
  count = var.enable_backup_notifications ? 1 : 0

  name              = "${local.name_prefix}-notifications"
  kms_master_key_id = var.kms_key_arn

  tags = var.tags
}

resource "aws_sns_topic_subscription" "backup_email" {
  count = var.enable_backup_notifications ? length(var.notification_emails) : 0

  topic_arn = aws_sns_topic.backup_notifications[0].arn
  protocol  = "email"
  endpoint  = var.notification_emails[count.index]
}

# Backup Vault Notifications
resource "aws_backup_vault_notifications" "main" {
  count = var.enable_backup_notifications ? 1 : 0

  backup_vault_name   = aws_backup_vault.main.name
  sns_topic_arn       = aws_sns_topic.backup_notifications[0].arn
  backup_vault_events = var.backup_vault_events
}

# CloudWatch Alarms for Backup Failures
resource "aws_cloudwatch_metric_alarm" "backup_failures" {
  count = var.enable_backup_notifications ? 1 : 0

  alarm_name          = "${local.name_prefix}-backup-failures"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "NumberOfBackupJobsFailed"
  namespace           = "AWS/Backup"
  period              = "3600"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "Backup jobs have failed"
  alarm_actions       = [aws_sns_topic.backup_notifications[0].arn]
  treat_missing_data  = "notBreaching"

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "restore_failures" {
  count = var.enable_backup_notifications ? 1 : 0

  alarm_name          = "${local.name_prefix}-restore-failures"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "NumberOfRestoreJobsFailed"
  namespace           = "AWS/Backup"
  period              = "3600"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "Restore jobs have failed"
  alarm_actions       = [aws_sns_topic.backup_notifications[0].arn]
  treat_missing_data  = "notBreaching"

  tags = var.tags
}

# Backup Report Plan
resource "aws_backup_report_plan" "main" {
  count = var.enable_backup_reports ? 1 : 0

  name        = "${local.name_prefix}-compliance-report"
  description = "Daily backup compliance report"

  report_delivery_channel {
    formats = ["CSV", "JSON"]
    s3_bucket_name = var.backup_reports_bucket
    s3_key_prefix  = "backup-reports/"
  }

  report_setting {
    report_template = "BACKUP_JOB_REPORT"
    accounts        = [data.aws_caller_identity.current.account_id]
    organization_units = var.organization_units
    regions         = [var.region]
  }

  tags = var.tags
}

# Lambda function for automated backup testing (optional)
resource "aws_lambda_function" "backup_testing" {
  count = var.enable_backup_testing ? 1 : 0

  filename         = "${path.module}/lambda/backup-testing.zip"
  function_name    = "${local.name_prefix}-testing"
  role             = aws_iam_role.backup_testing[0].arn
  handler          = "index.handler"
  source_code_hash = filebase64sha256("${path.module}/lambda/backup-testing.zip")
  runtime          = "python3.11"
  timeout          = 900
  memory_size      = 512

  environment {
    variables = {
      BACKUP_VAULT_NAME = aws_backup_vault.main.name
      TEST_TAG          = "BackupTest"
      ENVIRONMENT       = var.tags["Environment"]
    }
  }

  tags = var.tags
}

# IAM role for backup testing Lambda
resource "aws_iam_role" "backup_testing" {
  count = var.enable_backup_testing ? 1 : 0

  name = "${local.name_prefix}-testing-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "backup_testing_basic" {
  count = var.enable_backup_testing ? 1 : 0

  role       = aws_iam_role.backup_testing[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "backup_testing_custom" {
  count = var.enable_backup_testing ? 1 : 0

  name = "${local.name_prefix}-testing-policy"
  role = aws_iam_role.backup_testing[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "backup:ListRecoveryPointsByBackupVault",
          "backup:StartRestoreJob",
          "backup:DescribeRestoreJob",
          "ec2:CreateVolume",
          "ec2:DeleteVolume",
          "ec2:DescribeVolumes",
          "rds:RestoreDBInstanceFromDBSnapshot",
          "rds:DeleteDBInstance",
          "rds:DescribeDBInstances"
        ]
        Resource = "*"
      }
    ]
  })
}

# EventBridge rule for scheduled backup testing
resource "aws_cloudwatch_event_rule" "backup_testing" {
  count = var.enable_backup_testing ? 1 : 0

  name                = "${local.name_prefix}-testing-schedule"
  description         = "Trigger backup testing Lambda on schedule"
  schedule_expression = var.backup_testing_schedule

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "backup_testing" {
  count = var.enable_backup_testing ? 1 : 0

  rule      = aws_cloudwatch_event_rule.backup_testing[0].name
  target_id = "BackupTestingLambda"
  arn       = aws_lambda_function.backup_testing[0].arn
}

resource "aws_lambda_permission" "backup_testing" {
  count = var.enable_backup_testing ? 1 : 0

  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.backup_testing[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.backup_testing[0].arn
}

# Data sources
data "aws_caller_identity" "current" {}
