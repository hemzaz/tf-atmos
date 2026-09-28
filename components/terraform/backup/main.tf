locals {
  name_prefix = "${var.tags["Environment"]}-${lookup(var.tags, "Name", "backup")}"

  # The tag the restore-test Lambda sets on the resource its own restore job
  # creates, and the only tag its IAM policy (aws_iam_role_policy.backup_testing_custom)
  # will ever allow it to delete (M11 fix: no destructive action there carries
  # an unconditioned Resource "*" any more).
  restore_test_tag_key   = "BackupRestoreTest"
  restore_test_tag_value = "true"

  # Every RDS restore-test instance is named with this prefix (lambda/backup_testing.py's
  # _restore_metadata builds DBInstanceIdentifier from it). aws_iam_role_policy.backup_testing_custom
  # scopes rds:AddTagsToResource/rds:DeleteDBInstance to this ARN prefix so the
  # Lambda's own role can only ever touch a DB instance this test itself created
  # (defense in depth alongside the aws:RequestTag/aws:ResourceTag conditions
  # below -- a wrong ARN passed internally still can't reach a real database).
  restore_test_db_prefix = "${local.name_prefix}-restore-test-"

  # Built from known values (not aws_backup_vault.main.arn / aws_iam_role.backup.arn
  # / aws_sns_topic.backup_notifications[0].arn / aws_cloudwatch_metric_alarm.*.arn)
  # so the policies below are fully computable at `terraform plan` time -- all
  # of these ARN formats are deterministic, and tests/backup.tftest.hcl
  # asserts their JSON with `command = plan`.
  backup_vault_arn               = "arn:aws:backup:${var.region}:${data.aws_caller_identity.current.account_id}:backup-vault:${aws_backup_vault.main.name}"
  backup_service_role_arn        = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${aws_iam_role.backup.name}"
  backup_notifications_topic_arn = "arn:aws:sns:${var.region}:${data.aws_caller_identity.current.account_id}:${local.name_prefix}-notifications"
  backup_failures_alarm_arn      = "arn:aws:cloudwatch:${var.region}:${data.aws_caller_identity.current.account_id}:alarm:${local.name_prefix}-backup-failures"
  restore_failures_alarm_arn     = "arn:aws:cloudwatch:${var.region}:${data.aws_caller_identity.current.account_id}:alarm:${local.name_prefix}-restore-failures"
}

# AWS Backup Vault
resource "aws_backup_vault" "main" {
  name        = local.name_prefix
  kms_key_arn = var.kms_key_arn

  tags = { Name = local.name_prefix }
}

# Cross-Region Backup Vault (if enabled)
resource "aws_backup_vault" "cross_region" {
  count    = var.enable_cross_region_backup ? 1 : 0
  provider = aws.replica

  name        = "${local.name_prefix}-replica"
  kms_key_arn = var.replica_kms_key_arn

  tags = { Name = "${local.name_prefix}-replica" }
}

# Backup Vault Lock (compliance mode)
resource "aws_backup_vault_lock_configuration" "main" {
  count = var.enable_vault_lock ? 1 : 0

  backup_vault_name   = aws_backup_vault.main.name
  changeable_for_days = var.vault_lock_changeable_days
  min_retention_days  = var.vault_lock_min_retention_days
  max_retention_days  = var.vault_lock_max_retention_days

  # A locked vault rejects any backup or copy job whose retention falls
  # outside [min_retention_days, max_retention_days], so a plan rule with a
  # shorter or longer delete_after would only fail at job run time, after a
  # clean apply. Catch it at plan time instead, one check per cadence.
  lifecycle {
    precondition {
      condition     = var.daily_retention_days >= var.vault_lock_min_retention_days && var.daily_retention_days <= var.vault_lock_max_retention_days
      error_message = "daily_retention_days (${var.daily_retention_days}) must be within the vault lock range ${var.vault_lock_min_retention_days}-${var.vault_lock_max_retention_days} days, or the locked vault rejects daily backup jobs."
    }

    precondition {
      condition     = var.weekly_retention_days >= var.vault_lock_min_retention_days && var.weekly_retention_days <= var.vault_lock_max_retention_days
      error_message = "weekly_retention_days (${var.weekly_retention_days}) must be within the vault lock range ${var.vault_lock_min_retention_days}-${var.vault_lock_max_retention_days} days, or the locked vault rejects weekly backup jobs."
    }

    precondition {
      condition     = var.monthly_retention_days >= var.vault_lock_min_retention_days && var.monthly_retention_days <= var.vault_lock_max_retention_days
      error_message = "monthly_retention_days (${var.monthly_retention_days}) must be within the vault lock range ${var.vault_lock_min_retention_days}-${var.vault_lock_max_retention_days} days, or the locked vault rejects monthly backup jobs."
    }
  }
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
}

resource "aws_iam_role_policy_attachment" "backup" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_iam_role_policy_attachment" "restore" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

# Backup Plan: one plan with a daily/weekly/monthly rule each, mirroring
# cloudposse/terraform-aws-backup's model (a single aws_backup_plan built from
# var.rules, one rule per cadence) rather than one aws_backup_plan per cadence.
# This matters operationally, not just cosmetically: an aws_backup_selection
# attaches to a *plan*, and covers every rule inside that plan. Three separate
# plans would need three separate (or tripled) selections -- one per cadence --
# or the weekly/monthly rules simply never run against anything, which is
# exactly the bug this merge fixes (HIGH finding: weekly/monthly retention was
# unreachable because every selection below pointed only at the old daily-only
# plan).
resource "aws_backup_plan" "main" {
  name = local.name_prefix

  rule {
    rule_name         = "daily-backup"
    target_vault_name = aws_backup_vault.main.name
    schedule          = var.daily_backup_schedule
    start_window      = var.backup_start_window
    completion_window = var.backup_completion_window

    lifecycle {
      delete_after                              = var.daily_retention_days
      cold_storage_after                        = var.daily_cold_storage_days
      opt_in_to_archive_for_supported_resources = var.enable_archive_tier
    }

    dynamic "copy_action" {
      for_each = var.enable_cross_region_backup ? [aws_backup_vault.cross_region[0].arn] : []
      content {
        destination_vault_arn = copy_action.value

        lifecycle {
          delete_after       = var.daily_retention_days
          cold_storage_after = var.daily_cold_storage_days
        }
      }
    }

    recovery_point_tags = merge(
      var.tags,
      {
        BackupType = "Daily"
      }
    )
  }

  rule {
    rule_name         = "weekly-backup"
    target_vault_name = aws_backup_vault.main.name
    schedule          = var.weekly_backup_schedule
    start_window      = var.backup_start_window
    completion_window = var.backup_completion_window

    lifecycle {
      delete_after                              = var.weekly_retention_days
      cold_storage_after                        = var.weekly_cold_storage_days
      opt_in_to_archive_for_supported_resources = var.enable_archive_tier
    }

    dynamic "copy_action" {
      for_each = var.enable_cross_region_backup ? [aws_backup_vault.cross_region[0].arn] : []
      content {
        destination_vault_arn = copy_action.value

        lifecycle {
          delete_after       = var.weekly_retention_days
          cold_storage_after = var.weekly_cold_storage_days
        }
      }
    }

    recovery_point_tags = merge(
      var.tags,
      {
        BackupType = "Weekly"
      }
    )
  }

  rule {
    rule_name         = "monthly-backup"
    target_vault_name = aws_backup_vault.main.name
    schedule          = var.monthly_backup_schedule
    start_window      = var.backup_start_window
    completion_window = var.backup_completion_window

    lifecycle {
      delete_after                              = var.monthly_retention_days
      cold_storage_after                        = var.monthly_cold_storage_days
      opt_in_to_archive_for_supported_resources = var.enable_archive_tier
    }

    dynamic "copy_action" {
      for_each = var.enable_cross_region_backup ? [aws_backup_vault.cross_region[0].arn] : []
      content {
        destination_vault_arn = copy_action.value

        lifecycle {
          delete_after       = var.monthly_retention_days
          cold_storage_after = var.monthly_cold_storage_days
        }
      }
    }

    recovery_point_tags = merge(
      var.tags,
      {
        BackupType = "Monthly"
      }
    )
  }

  advanced_backup_setting {
    backup_options = {
      WindowsVSS = "enabled"
    }
    resource_type = "EC2"
  }

  # HIGH fix (round-5 review): AWS Backup requires a recovery point to sit in
  # cold storage for at least 90 days before it can be deleted, so
  # CreateBackupPlan/UpdateBackupPlan rejects any rule whose
  # delete_after < cold_storage_after + 90. That combination previously had
  # no guard anywhere -- not in these variables, not in a test -- so a stack
  # could set a *_cold_storage_days override together with a shorter
  # retention (e.g. a dev/staging monthly_retention_days of 30/90) and the
  # break would only surface as an apply-time InvalidParameterValueException,
  # after the plan sweep and every other check already passed. These
  # preconditions turn that into a `terraform plan` failure with a clear
  # message, one per cadence. All three *_cold_storage_days variables default
  # to null (off), matching cloudposse/terraform-aws-backup's
  # rules[].lifecycle.cold_storage_after; only an instance that opts in with
  # a long enough retention (e.g. this repo's prod instance) needs these
  # preconditions at all.
  lifecycle {
    precondition {
      condition     = var.daily_cold_storage_days == null || var.daily_retention_days >= var.daily_cold_storage_days + 90
      error_message = "daily_retention_days (${var.daily_retention_days}) must be at least daily_cold_storage_days (${coalesce(var.daily_cold_storage_days, 0)}) + 90: AWS Backup keeps a recovery point in cold storage for a minimum of 90 days before it can be deleted."
    }

    precondition {
      condition     = var.weekly_cold_storage_days == null || var.weekly_retention_days >= var.weekly_cold_storage_days + 90
      error_message = "weekly_retention_days (${var.weekly_retention_days}) must be at least weekly_cold_storage_days (${coalesce(var.weekly_cold_storage_days, 0)}) + 90: AWS Backup keeps a recovery point in cold storage for a minimum of 90 days before it can be deleted."
    }

    precondition {
      condition     = var.monthly_cold_storage_days == null || var.monthly_retention_days >= var.monthly_cold_storage_days + 90
      error_message = "monthly_retention_days (${var.monthly_retention_days}) must be at least monthly_cold_storage_days (${coalesce(var.monthly_cold_storage_days, 0)}) + 90: AWS Backup keeps a recovery point in cold storage for a minimum of 90 days before it can be deleted."
    }
  }
}

# Backup Selection for RDS, by explicit ARN list
resource "aws_backup_selection" "rds_daily" {
  count = length(var.rds_instances) > 0 ? 1 : 0

  name         = "${local.name_prefix}-rds-explicit"
  plan_id      = aws_backup_plan.main.id
  iam_role_arn = aws_iam_role.backup.arn

  resources = [for instance in var.rds_instances : "arn:aws:rds:${var.region}:${data.aws_caller_identity.current.account_id}:db:${instance}"]
}

# Backup Selection for RDS by tag. Selecting by tag (rather than by reading
# rds state) keeps this component decoupled from rds/main and rds/data:
# workflows/deploy-full-stack.yaml runs backup in the same "data" phase as
# rds, and workflows/scripts/common/check-deploy-layers.py rejects a
# same-phase !terraform.state read. rds/main and rds/data set Backup=true in
# their own stack vars.tags to opt in.
#
# CRITICAL fix: this used to be two `selection_tag` blocks (Backup=true,
# Environment=<env>). BackupSelection.ListOfTags combines multiple
# selection_tag entries with OR, not AND, so that selected every RDS instance
# with EITHER tag -- in practice every RDS instance in the account, since
# Environment is set on all of them via provider default_tags. `resources`
# (an RDS-only ARN pattern) plus a `condition` block (AND semantics, per
# cloudposse/terraform-aws-backup's `conditions` selection style) is the fix:
# only RDS instances matching the ARN pattern AND carrying both tags qualify.
resource "aws_backup_selection" "rds_tagged_daily" {
  count = var.enable_rds_backup ? 1 : 0

  name         = "${local.name_prefix}-rds-tagged"
  plan_id      = aws_backup_plan.main.id
  iam_role_arn = aws_iam_role.backup.arn

  resources = ["arn:aws:rds:${var.region}:${data.aws_caller_identity.current.account_id}:db:*"]

  # MEDIUM fix (round-2 review), corrected in round-3: rds/main and rds/data
  # set Backup=true in their own var.tags, which reaches every resource they
  # create, including a `create_read_replica = true` instance's
  # aws_db_instance.read_replica. AWS Backup's handling of RDS read replicas
  # is restricted (it cannot be backed up independently of its source), so
  # without an exclusion the replica would either duplicate the source's
  # snapshots or fail its own backup job and fire the
  # NumberOfBackupJobsFailed alarm.
  #
  # The round-2 fix used `not_resources` with a leading-wildcard pattern
  # ("*-read-replica"), which the BackupSelection API rejects: per its
  # reference, a wildcard in an ARN pattern must appear at the end (a prefix
  # match, e.g. "my-bucket-*"), never at the start, so that pattern would
  # either fail CreateBackupSelection at apply time or silently not exclude
  # anything. Excluding by a `string_not_equals` condition on the tag
  # rds/main already sets on the replica (`Role = "read-replica"`,
  # rds/main.tf's aws_db_instance.read_replica) avoids ARN wildcards
  # entirely, and AWS Backup's `Conditions` parameter ANDs every condition in
  # the block together (unlike `ListOfTags`, which ORs), so this narrows the
  # existing Backup=true/Environment=<env> selection rather than replacing
  # its semantics.
  condition {
    string_equals {
      key   = "aws:ResourceTag/Backup"
      value = "true"
    }
    string_equals {
      key   = "aws:ResourceTag/Environment"
      value = var.tags["Environment"]
    }
    string_not_equals {
      key   = "aws:ResourceTag/Role"
      value = "read-replica"
    }
  }
}

# Backup Selection for DynamoDB
resource "aws_backup_selection" "dynamodb_daily" {
  count = length(var.dynamodb_tables) > 0 ? 1 : 0

  name         = "${local.name_prefix}-dynamodb"
  plan_id      = aws_backup_plan.main.id
  iam_role_arn = aws_iam_role.backup.arn

  resources = [for table in var.dynamodb_tables : "arn:aws:dynamodb:${var.region}:${data.aws_caller_identity.current.account_id}:table/${table}"]
}

# Backup Selection for EFS
resource "aws_backup_selection" "efs_daily" {
  count = length(var.efs_file_systems) > 0 ? 1 : 0

  name         = "${local.name_prefix}-efs"
  plan_id      = aws_backup_plan.main.id
  iam_role_arn = aws_iam_role.backup.arn

  resources = [for fs in var.efs_file_systems : "arn:aws:elasticfilesystem:${var.region}:${data.aws_caller_identity.current.account_id}:file-system/${fs}"]
}

# Backup Selection for EC2 (by tags). Same CRITICAL fix as rds_tagged_daily
# above: ARN pattern scoped to EC2 instances plus an AND'd condition block,
# not two OR'd selection_tag entries.
resource "aws_backup_selection" "ec2_daily" {
  count = var.enable_ec2_backup ? 1 : 0

  name         = "${local.name_prefix}-ec2-tagged"
  plan_id      = aws_backup_plan.main.id
  iam_role_arn = aws_iam_role.backup.arn

  resources = ["arn:aws:ec2:${var.region}:${data.aws_caller_identity.current.account_id}:instance/*"]

  condition {
    string_equals {
      key   = "aws:ResourceTag/Backup"
      value = "true"
    }
    string_equals {
      key   = "aws:ResourceTag/Environment"
      value = var.tags["Environment"]
    }
  }
}

# Backup Selection for EBS Volumes, by explicit ARN list (mirrors rds_daily above)
resource "aws_backup_selection" "ebs_daily" {
  count = length(var.ebs_volume_ids) > 0 ? 1 : 0

  name         = "${local.name_prefix}-ebs-explicit"
  plan_id      = aws_backup_plan.main.id
  iam_role_arn = aws_iam_role.backup.arn

  resources = [for vol in var.ebs_volume_ids : "arn:aws:ec2:${var.region}:${data.aws_caller_identity.current.account_id}:volume/${vol}"]
}

# Backup Selection for EBS Volumes, by tag (mirrors rds_tagged_daily/ec2_daily
# above). The pre-fix version of this selection used a single selection_tag
# (Backup=true only, no Environment) with no resource-type ARN scoping at
# all, which per the BackupSelection API selects every backup-supported
# resource type carrying that tag, not just EBS volumes, and does not match
# this component's own README ("Backup=true + Environment=..."). Now scoped
# to EBS volumes specifically, AND'd with both tags like the other two.
resource "aws_backup_selection" "ebs_tagged_daily" {
  count = var.enable_ebs_backup ? 1 : 0

  name         = "${local.name_prefix}-ebs-tagged"
  plan_id      = aws_backup_plan.main.id
  iam_role_arn = aws_iam_role.backup.arn

  resources = ["arn:aws:ec2:${var.region}:${data.aws_caller_identity.current.account_id}:volume/*"]

  condition {
    string_equals {
      key   = "aws:ResourceTag/Backup"
      value = "true"
    }
    string_equals {
      key   = "aws:ResourceTag/Environment"
      value = var.tags["Environment"]
    }
  }
}

# Backup Notifications
resource "aws_sns_topic" "backup_notifications" {
  count = var.enable_backup_notifications ? 1 : 0

  name              = "${local.name_prefix}-notifications"
  kms_master_key_id = var.kms_key_arn
}

resource "aws_sns_topic_subscription" "backup_email" {
  count = var.enable_backup_notifications ? length(var.notification_emails) : 0

  topic_arn = aws_sns_topic.backup_notifications[0].arn
  protocol  = "email"
  endpoint  = var.notification_emails[count.index]
}

# HIGH fix: aws_backup_vault_notifications alone does not let AWS Backup
# publish to the topic -- it also needs an access policy statement allowing
# backup.amazonaws.com to SNS:Publish (see the aws_backup_vault_notifications
# registry example), same as this repo's own
# aws_sns_topic_policy.security_alerts pattern in security-monitoring/main.tf.
# The alarms below (backup_failures/restore_failures) publish to this same
# topic, so cloudwatch.amazonaws.com is allowed too, scoped to those two
# alarm ARNs specifically.
resource "aws_sns_topic_policy" "backup_notifications" {
  count = var.enable_backup_notifications ? 1 : 0

  arn = aws_sns_topic.backup_notifications[0].arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowBackupToPublish"
        Effect = "Allow"
        Principal = {
          Service = "backup.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = local.backup_notifications_topic_arn
        Condition = {
          StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
        }
      },
      {
        Sid    = "AllowBackupAlarmsToPublish"
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = local.backup_notifications_topic_arn
        Condition = {
          StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
          ArnEquals = {
            "aws:SourceArn" = [
              local.backup_failures_alarm_arn,
              local.restore_failures_alarm_arn,
            ]
          }
        }
      }
    ]
  })
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
}

# Backup Report Plan
resource "aws_backup_report_plan" "main" {
  count = var.enable_backup_reports ? 1 : 0

  name        = "${local.name_prefix}-compliance-report"
  description = "Daily backup compliance report"

  report_delivery_channel {
    formats        = ["CSV", "JSON"]
    s3_bucket_name = var.backup_reports_bucket
    s3_key_prefix  = "backup-reports/"
  }

  report_setting {
    report_template    = "BACKUP_JOB_REPORT"
    accounts           = [data.aws_caller_identity.current.account_id]
    organization_units = var.organization_units
    regions            = [var.region]
  }
}

# Lambda deployment package, built from the committed source at plan/apply
# time (the components/terraform/cost-optimization pattern) rather than a
# committed zip.
data "archive_file" "backup_testing_lambda" {
  count = var.enable_backup_testing ? 1 : 0

  type        = "zip"
  output_path = "${path.module}/backup_testing_lambda.zip"

  source {
    content  = file("${path.module}/lambda/backup_testing.py")
    filename = "index.py"
  }
}

# LOW fix: without an explicit log group, Lambda auto-creates
# /aws/lambda/<name> with no retention and no CMK encryption -- this repo's
# encrypt-at-rest convention -- the components/terraform/cost-optimization
# pattern (lambda.tf's aws_cloudwatch_log_group.scheduler/etc.) creates the
# log group itself, ahead of the function, so it can reference a real ARN.
# kms/main already grants logs.<region>.amazonaws.com via allow_cloudwatch_logs
# in catalog/kms/defaults.yaml, so this key can encrypt it.
resource "aws_cloudwatch_log_group" "backup_testing" {
  count = var.enable_backup_testing ? 1 : 0

  name              = "/aws/lambda/${local.name_prefix}-testing"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = { Name = "/aws/lambda/${local.name_prefix}-testing" }
}

# Lambda function for automated backup testing (optional)
resource "aws_lambda_function" "backup_testing" {
  count = var.enable_backup_testing ? 1 : 0

  filename         = data.archive_file.backup_testing_lambda[0].output_path
  function_name    = "${local.name_prefix}-testing"
  role             = aws_iam_role.backup_testing[0].arn
  handler          = "index.handler"
  source_code_hash = data.archive_file.backup_testing_lambda[0].output_base64sha256
  runtime          = "python3.11"
  timeout          = 900
  memory_size      = 512

  environment {
    variables = {
      BACKUP_VAULT_NAME          = aws_backup_vault.main.name
      RESTORE_IAM_ROLE_ARN       = local.backup_service_role_arn
      TEST_TAG_KEY               = local.restore_test_tag_key
      TEST_TAG_VALUE             = local.restore_test_tag_value
      RESOURCE_TYPE              = var.backup_testing_resource_type
      ENVIRONMENT                = var.tags["Environment"]
      RDS_RESTORE_TEST_DB_PREFIX = local.restore_test_db_prefix
    }
  }

  depends_on = [aws_cloudwatch_log_group.backup_testing]
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
}

resource "aws_iam_role_policy_attachment" "backup_testing_basic" {
  count = var.enable_backup_testing ? 1 : 0

  role       = aws_iam_role.backup_testing[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# M11 fix, hardened further below: the previous version of this policy
# allowed ec2:DeleteVolume and rds:DeleteDBInstance (plus the Create/Restore
# actions) on Resource "*" with no condition, so a bug in the restore-test
# Lambda could delete ANY volume or database in the account. Now:
#   - backup:* is scoped to this component's own vault, not "*".
#   - ec2:CreateVolume / rds:RestoreDBInstanceFromDBSnapshot are not granted
#     here at all: AWS Backup performs the actual restore under the passed
#     backup service role (PassBackupServiceRoleForRestore below), which
#     already carries AWSBackupServiceRolePolicyForRestores.
#   - ec2:CreateTags / rds:AddTagsToResource require the request itself to
#     set the BackupRestoreTest marker tag (aws:RequestTag).
#   - ec2:DeleteVolume / rds:DeleteDBInstance require the target resource to
#     already carry that same tag (aws:ResourceTag).
#
# HIGH fix: request-tag/resource-tag conditions alone are bypassable -- this
# role could ec2:CreateTags/rds:AddTagsToResource onto ANY existing resource
# (Resource "*") as long as the request set BackupRestoreTest=true, then
# ec2:DeleteVolume/rds:DeleteDBInstance it, so a bug in
# lambda/backup_testing.py that passes the wrong ARN into
# _tag_restored_resource/_delete_restored_resource could tag-and-delete a
# real, in-use resource, not just its own restore-test resource. Two
# independent layers now bound what can be tagged, not only what the tag
# says:
#   - RDS: rds:AddTagsToResource/rds:DeleteDBInstance are scoped by Resource
#     ARN to local.restore_test_db_prefix* -- lambda/backup_testing.py names
#     every RDS restore-test instance under that exact prefix, so this role
#     cannot reach a real database's ARN no matter what tag the request sets.
#   - EC2 (ec2:CreateTags/ec2:DeleteVolume): both actions DO support
#     resource-level ARN scoping to the volume resource type (see the AWS
#     "Resource-level permissions for EC2 API actions" reference -- `volume`
#     is a listed resource type for both), so both are scoped to
#     "arn:...:volume/*", not "*". The Null condition (target has no
#     Environment tag yet) narrows this further for most volumes, but it is
#     NOT sufficient on its own in this repo: eks-addons installs
#     aws-ebs-csi-driver as a core addon in every cluster
#     (components/terraform/eks-addons/main.tf), and every EBS volume it
#     provisions for a Kubernetes PersistentVolume carries only CSI/k8s
#     tags -- no Environment tag, since the CSI driver creates volumes
#     through its own AWS API calls, not through this repo's Terraform, so
#     `default_tags` never reaches them. Those volumes are real, in-use
#     application data (for example Retain-policy PVs or scaled-down
#     StatefulSets), not just "untagged". The third Deny below closes that
#     gap: the AWS EBS CSI driver tags every volume and snapshot it manages
#     with "ebs.csi.aws.com/cluster" = "true" unconditionally, by default,
#     independent of any `--k8s-tag-cluster-id`/`extraVolumeTags`
#     configuration (upstream kubernetes-sigs/aws-ebs-csi-driver
#     docs/tagging.md, "Default Cluster Tag"), so this Deny reaches every
#     CSI-managed volume even one that -- through a future addon config
#     change or a manually created PV -- ends up without an Environment tag.
#   - Three final explicit Denies (not merely omitting an Allow) block all
#     four of CreateTags/AddTagsToResource/DeleteVolume/DeleteDBInstance
#     outright on any resource that already carries an Environment tag,
#     already carries a Backup=true tag, or is a CSI/Kubernetes-managed EBS
#     volume, as a backstop that holds even if the scoping above is ever
#     loosened by mistake. All three Denies list the RDS actions too, even
#     though the RDS Allow grants above are already ARN-prefix scoped to the
#     restore-test namespace and a freshly restored RDS instance carries
#     neither the Environment nor the CSI tag -- this is defense in depth,
#     not a live restriction on today's restore-test flow.
resource "aws_iam_role_policy" "backup_testing_custom" {
  count = var.enable_backup_testing ? 1 : 0

  name = "${local.name_prefix}-testing-policy"
  role = aws_iam_role.backup_testing[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # HIGH fix (independent review round-1 of the merge to master): only
        # backup:ListRecoveryPointsByBackupVault actually authorizes against
        # the backupVault resource type. It was the only one of these four
        # actions that belonged on the vault ARN.
        Sid      = "ListRecoveryPointsInOwnVault"
        Effect   = "Allow"
        Action   = "backup:ListRecoveryPointsByBackupVault"
        Resource = local.backup_vault_arn
      },
      {
        # HIGH fix: per the AWS Backup IAM Service Authorization reference,
        # backup:StartRestoreJob and backup:GetRecoveryPointRestoreMetadata
        # both authorize against the recoveryPoint* resource type -- the
        # underlying resource's own ARN (an EC2 snapshot or an RDS
        # snapshot:awsbackup:* snapshot), never the backup vault ARN. Scoping
        # them to local.backup_vault_arn made both calls AccessDenied at
        # runtime, so lambda/backup_testing.py's restore test never actually
        # ran (get_recovery_point_restore_metadata first, then
        # start_restore_job) -- latent today only because
        # enable_backup_testing defaults to false in every stack.
        #
        # MEDIUM fix (kept from the previous version): seeds _restore_metadata
        # from the source recovery point's own restore metadata
        # (availabilityZone, subnet group, security groups, encryption, etc.)
        # instead of guessing a bare DBInstanceIdentifier/availabilityZone,
        # which is the AWS Backup registry's documented pattern for
        # StartRestoreJob's Metadata arg.
        Sid    = "StartRestoreAndGetMetadataForOwnEnvironmentRecoveryPoints"
        Effect = "Allow"
        Action = [
          "backup:StartRestoreJob",
          "backup:GetRecoveryPointRestoreMetadata",
        ]
        # EC2 recovery points restore from an unnamed account-wide snapshot
        # (AWS Backup manages the underlying snap-* id, not this component),
        # so the EC2 branch is a resource-type wildcard rather than a single
        # ARN; RDS and AWS Backup's own recovery-point ARNs are similarly
        # unnamed until the recovery point exists. The aws:ResourceTag
        # condition below is what actually narrows this to recovery points
        # this component's own backup plan created (recovery_point_tags on
        # every rule above sets Environment from var.tags).
        Resource = [
          "arn:aws:ec2:${var.region}::snapshot/*",
          "arn:aws:rds:${var.region}:${data.aws_caller_identity.current.account_id}:snapshot:awsbackup:*",
          "arn:aws:backup:${var.region}:${data.aws_caller_identity.current.account_id}:recovery-point:*",
        ]
        Condition = {
          StringEquals = {
            "aws:ResourceTag/Environment" = var.tags["Environment"]
          }
        }
      },
      {
        # HIGH fix: backup:DescribeRestoreJob has no resource type in the IAM
        # Service Authorization reference at all -- it must be Resource "*".
        # It only ever reads back the status of a restore job this role
        # itself started (via StartRestoreJob above), so this is not a
        # meaningful widening of what the role can do.
        Sid      = "DescribeAnyRestoreJob"
        Effect   = "Allow"
        Action   = "backup:DescribeRestoreJob"
        Resource = "*"
      },
      {
        Sid      = "PassBackupServiceRoleForRestore"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = local.backup_service_role_arn
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "backup.amazonaws.com"
          }
        }
      },
      {
        Sid      = "DescribeRestoredResources"
        Effect   = "Allow"
        Action   = ["ec2:DescribeVolumes", "ec2:DescribeAvailabilityZones", "rds:DescribeDBInstances"]
        Resource = "*"
      },
      {
        Sid      = "TagRestoredEbsVolumesOnlyBeforeTheyAreEnvironmentManaged"
        Effect   = "Allow"
        Action   = "ec2:CreateTags"
        Resource = "arn:aws:ec2:${var.region}:${data.aws_caller_identity.current.account_id}:volume/*"
        Condition = {
          StringEquals = {
            "aws:RequestTag/${local.restore_test_tag_key}" = local.restore_test_tag_value
          }
          Null = {
            "aws:ResourceTag/Environment" = "true"
          }
        }
      },
      {
        Sid      = "TagRestoredRdsInstancesOnlyUnderTheRestoreTestPrefix"
        Effect   = "Allow"
        Action   = "rds:AddTagsToResource"
        Resource = "arn:aws:rds:${var.region}:${data.aws_caller_identity.current.account_id}:db:${local.restore_test_db_prefix}*"
        Condition = {
          StringEquals = {
            "aws:RequestTag/${local.restore_test_tag_key}" = local.restore_test_tag_value
          }
        }
      },
      {
        Sid      = "DeleteOnlyEbsVolumesTaggedByThisTest"
        Effect   = "Allow"
        Action   = "ec2:DeleteVolume"
        Resource = "arn:aws:ec2:${var.region}:${data.aws_caller_identity.current.account_id}:volume/*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/${local.restore_test_tag_key}" = local.restore_test_tag_value
          }
        }
      },
      {
        Sid      = "DeleteOnlyRdsInstancesUnderTheRestoreTestPrefix"
        Effect   = "Allow"
        Action   = "rds:DeleteDBInstance"
        Resource = "arn:aws:rds:${var.region}:${data.aws_caller_identity.current.account_id}:db:${local.restore_test_db_prefix}*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/${local.restore_test_tag_key}" = local.restore_test_tag_value
          }
        }
      },
      {
        Sid      = "DenyTaggingOrDeletingEnvironmentManagedResources"
        Effect   = "Deny"
        Action   = ["ec2:CreateTags", "ec2:DeleteVolume", "rds:AddTagsToResource", "rds:DeleteDBInstance"]
        Resource = "*"
        Condition = {
          Null = {
            "aws:ResourceTag/Environment" = "false"
          }
        }
      },
      {
        Sid      = "DenyTaggingOrDeletingBackupOptedInResources"
        Effect   = "Deny"
        Action   = ["ec2:CreateTags", "ec2:DeleteVolume", "rds:AddTagsToResource", "rds:DeleteDBInstance"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/Backup" = "true"
          }
        }
      },
      {
        # HIGH fix (round-2 review): the Null-Environment-tag condition above
        # is not sufficient on its own -- every EBS volume the eks-addons
        # aws-ebs-csi-driver addon provisions for a Kubernetes
        # PersistentVolume carries only CSI/k8s tags, never Environment (see
        # the comment above aws_iam_role_policy.backup_testing_custom). The
        # AWS EBS CSI driver tags every volume and snapshot it manages with
        # "ebs.csi.aws.com/cluster" = "true" unconditionally by default
        # (upstream docs/tagging.md, "Default Cluster Tag"), so this Deny
        # blocks all four actions on any such volume outright, regardless of
        # whether it also happens to carry an Environment tag.
        Sid      = "DenyTaggingOrDeletingCsiManagedEbsVolumes"
        Effect   = "Deny"
        Action   = ["ec2:CreateTags", "ec2:DeleteVolume", "rds:AddTagsToResource", "rds:DeleteDBInstance"]
        Resource = "*"
        Condition = {
          Null = {
            "aws:ResourceTag/ebs.csi.aws.com/cluster" = "false"
          }
        }
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
