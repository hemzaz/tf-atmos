locals {
  name_prefix = "${var.name_prefix}-${var.environment}"

  common_tags = merge(
    {
      Name        = "${local.name_prefix}-fsx-lustre"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Module      = "fsx-lustre"
    },
    var.tags
  )
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

#------------------------------------------------------------------------------
# KMS Key for FSx Encryption
#------------------------------------------------------------------------------
resource "aws_kms_key" "fsx" {
  count = var.enable_encryption && var.kms_key_id == null ? 1 : 0

  description             = "KMS key for FSx Lustre ${local.name_prefix}"
  deletion_window_in_days = var.kms_deletion_window_days
  enable_key_rotation     = true

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-fsx-kms"
    }
  )
}

resource "aws_kms_alias" "fsx" {
  count = var.enable_encryption && var.kms_key_id == null ? 1 : 0

  name          = "alias/${local.name_prefix}-fsx-lustre"
  target_key_id = aws_kms_key.fsx[0].key_id
}

#------------------------------------------------------------------------------
# S3 Bucket for Data Repository (optional)
#------------------------------------------------------------------------------
resource "aws_s3_bucket" "data_repository" {
  count = var.create_s3_bucket ? 1 : 0

  bucket        = "${local.name_prefix}-fsx-data-repo"
  force_destroy = var.s3_force_destroy

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-fsx-data-repo"
    }
  )
}

resource "aws_s3_bucket_versioning" "data_repository" {
  count = var.create_s3_bucket ? 1 : 0

  bucket = aws_s3_bucket.data_repository[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data_repository" {
  count = var.create_s3_bucket ? 1 : 0

  bucket = aws_s3_bucket.data_repository[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

#------------------------------------------------------------------------------
# FSx Lustre File System
#------------------------------------------------------------------------------
resource "aws_fsx_lustre_file_system" "this" {
  storage_capacity            = var.storage_capacity_gb
  subnet_ids                  = var.deployment_type == "PERSISTENT_1" || var.deployment_type == "PERSISTENT_2" ? [var.subnet_id] : [var.subnet_id]
  security_group_ids          = var.security_group_ids
  deployment_type             = var.deployment_type
  storage_type                = var.storage_type
  per_unit_storage_throughput = var.per_unit_storage_throughput

  kms_key_id = var.enable_encryption ? (var.kms_key_id != null ? var.kms_key_id : aws_kms_key.fsx[0].arn) : null

  automatic_backup_retention_days = var.deployment_type != "SCRATCH_1" && var.deployment_type != "SCRATCH_2" ? var.automatic_backup_retention_days : null
  daily_automatic_backup_start_time = var.deployment_type != "SCRATCH_1" && var.deployment_type != "SCRATCH_2" ? var.daily_automatic_backup_start_time : null
  copy_tags_to_backups            = var.deployment_type != "SCRATCH_1" && var.deployment_type != "SCRATCH_2" ? var.copy_tags_to_backups : null

  weekly_maintenance_start_time = var.weekly_maintenance_start_time

  data_compression_type = var.data_compression_type
  import_path           = var.s3_import_path != null ? var.s3_import_path : (var.create_s3_bucket ? "s3://${aws_s3_bucket.data_repository[0].id}" : null)
  export_path           = var.s3_export_path != null ? var.s3_export_path : (var.create_s3_bucket ? "s3://${aws_s3_bucket.data_repository[0].id}" : null)
  imported_file_chunk_size = var.imported_file_chunk_size

  dynamic "log_configuration" {
    for_each = var.enable_logging ? [1] : []

    content {
      level       = var.log_level
      destination = var.log_destination_arn
    }
  }

  tags = local.common_tags
}

#------------------------------------------------------------------------------
# Data Repository Association (DRA)
#------------------------------------------------------------------------------
resource "aws_fsx_data_repository_association" "this" {
  for_each = var.data_repository_associations

  file_system_id       = aws_fsx_lustre_file_system.this.id
  data_repository_path = each.value.data_repository_path
  file_system_path     = each.value.file_system_path

  batch_import_meta_data_on_create = lookup(each.value, "batch_import_meta_data_on_create", false)
  imported_file_chunk_size         = lookup(each.value, "imported_file_chunk_size", null)

  dynamic "s3" {
    for_each = lookup(each.value, "s3_auto_import_policy", null) != null || lookup(each.value, "s3_auto_export_policy", null) != null ? [1] : []

    content {
      auto_import_policy {
        events = lookup(each.value, "s3_auto_import_policy", ["NEW", "CHANGED", "DELETED"])
      }

      auto_export_policy {
        events = lookup(each.value, "s3_auto_export_policy", ["NEW", "CHANGED", "DELETED"])
      }
    }
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-dra-${each.key}"
    }
  )
}

#------------------------------------------------------------------------------
# CloudWatch Log Group
#------------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "fsx" {
  count = var.enable_logging && var.log_destination_arn == null ? 1 : 0

  name              = "/aws/fsx/${local.name_prefix}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.enable_encryption && var.kms_key_id != null ? var.kms_key_id : (var.enable_encryption ? aws_kms_key.fsx[0].arn : null)

  tags = local.common_tags
}

#------------------------------------------------------------------------------
# CloudWatch Alarms
#------------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "storage_used" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.name_prefix}-fsx-storage-used-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "StorageUsed"
  namespace           = "AWS/FSx"
  period              = 300
  statistic           = "Average"
  threshold           = var.storage_capacity_gb * 1024 * 1024 * 1024 * var.storage_used_threshold_percent / 100
  alarm_description   = "FSx Lustre storage used is high"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FileSystemId = aws_fsx_lustre_file_system.this.id
  }

  alarm_actions = var.alarm_actions

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "free_data_storage" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.name_prefix}-fsx-free-storage-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "FreeDataStorageCapacity"
  namespace           = "AWS/FSx"
  period              = 300
  statistic           = "Average"
  threshold           = var.storage_capacity_gb * 1024 * 1024 * 1024 * (100 - var.storage_used_threshold_percent) / 100
  alarm_description   = "FSx Lustre free storage is low"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FileSystemId = aws_fsx_lustre_file_system.this.id
  }

  alarm_actions = var.alarm_actions

  tags = local.common_tags
}
