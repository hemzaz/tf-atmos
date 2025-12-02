locals {
  name_prefix = "${var.name_prefix}-${var.environment}"

  common_tags = merge(
    {
      Name        = "${local.name_prefix}-efs"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Module      = "efs-filesystem"
    },
    var.tags
  )
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

#------------------------------------------------------------------------------
# KMS Key for EFS Encryption
#------------------------------------------------------------------------------
resource "aws_kms_key" "efs" {
  count = var.enable_encryption && var.kms_key_id == null ? 1 : 0

  description             = "KMS key for EFS ${local.name_prefix}"
  deletion_window_in_days = var.kms_deletion_window_days
  enable_key_rotation     = true

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-efs-kms"
    }
  )
}

resource "aws_kms_alias" "efs" {
  count = var.enable_encryption && var.kms_key_id == null ? 1 : 0

  name          = "alias/${local.name_prefix}-efs"
  target_key_id = aws_kms_key.efs[0].key_id
}

#------------------------------------------------------------------------------
# EFS File System
#------------------------------------------------------------------------------
resource "aws_efs_file_system" "this" {
  creation_token = "${local.name_prefix}-efs"

  encrypted  = var.enable_encryption
  kms_key_id = var.enable_encryption ? (var.kms_key_id != null ? var.kms_key_id : aws_kms_key.efs[0].arn) : null

  performance_mode                = var.performance_mode
  throughput_mode                 = var.throughput_mode
  provisioned_throughput_in_mibps = var.throughput_mode == "provisioned" ? var.provisioned_throughput_in_mibps : null

  lifecycle_policy {
    transition_to_ia = var.transition_to_ia
  }

  dynamic "lifecycle_policy" {
    for_each = var.transition_to_archive != null ? [1] : []

    content {
      transition_to_archive = var.transition_to_archive
    }
  }

  dynamic "lifecycle_policy" {
    for_each = var.transition_to_primary_storage_class != null ? [1] : []

    content {
      transition_to_primary_storage_class = var.transition_to_primary_storage_class
    }
  }

  tags = local.common_tags
}

#------------------------------------------------------------------------------
# EFS Mount Targets
#------------------------------------------------------------------------------
resource "aws_efs_mount_target" "this" {
  for_each = toset(var.subnet_ids)

  file_system_id  = aws_efs_file_system.this.id
  subnet_id       = each.value
  security_groups = var.security_group_ids

  lifecycle {
    create_before_destroy = true
  }
}

#------------------------------------------------------------------------------
# EFS Access Points
#------------------------------------------------------------------------------
resource "aws_efs_access_point" "this" {
  for_each = var.access_points

  file_system_id = aws_efs_file_system.this.id

  posix_user {
    gid            = each.value.posix_user.gid
    uid            = each.value.posix_user.uid
    secondary_gids = lookup(each.value.posix_user, "secondary_gids", null)
  }

  root_directory {
    path = each.value.root_directory.path

    creation_info {
      owner_gid   = each.value.root_directory.creation_info.owner_gid
      owner_uid   = each.value.root_directory.creation_info.owner_uid
      permissions = each.value.root_directory.creation_info.permissions
    }
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-${each.key}"
    },
    lookup(each.value, "tags", {})
  )
}

#------------------------------------------------------------------------------
# EFS Backup Policy
#------------------------------------------------------------------------------
resource "aws_efs_backup_policy" "this" {
  count = var.enable_backup_policy ? 1 : 0

  file_system_id = aws_efs_file_system.this.id

  backup_policy {
    status = "ENABLED"
  }
}

#------------------------------------------------------------------------------
# EFS File System Policy
#------------------------------------------------------------------------------
resource "aws_efs_file_system_policy" "this" {
  count = var.file_system_policy != null ? 1 : 0

  file_system_id = aws_efs_file_system.this.id
  policy         = var.file_system_policy
}

#------------------------------------------------------------------------------
# CloudWatch Alarms
#------------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "burst_credit_balance" {
  count = var.enable_cloudwatch_alarms && var.performance_mode == "generalPurpose" ? 1 : 0

  alarm_name          = "${local.name_prefix}-efs-burst-credit-balance-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "BurstCreditBalance"
  namespace           = "AWS/EFS"
  period              = 300
  statistic           = "Average"
  threshold           = var.burst_credit_balance_threshold
  alarm_description   = "EFS burst credit balance is low"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FileSystemId = aws_efs_file_system.this.id
  }

  alarm_actions = var.alarm_actions

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "client_connections" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.name_prefix}-efs-client-connections-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ClientConnections"
  namespace           = "AWS/EFS"
  period              = 300
  statistic           = "Sum"
  threshold           = var.client_connections_threshold
  alarm_description   = "EFS client connections are high"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FileSystemId = aws_efs_file_system.this.id
  }

  alarm_actions = var.alarm_actions

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "percent_io_limit" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.name_prefix}-efs-percent-io-limit-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "PercentIOLimit"
  namespace           = "AWS/EFS"
  period              = 300
  statistic           = "Average"
  threshold           = var.percent_io_limit_threshold
  alarm_description   = "EFS percent IO limit is high"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FileSystemId = aws_efs_file_system.this.id
  }

  alarm_actions = var.alarm_actions

  tags = local.common_tags
}
