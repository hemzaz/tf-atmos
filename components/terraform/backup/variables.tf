variable "region" {
  type        = string
  description = "AWS region"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-\\d+$", var.region))
    error_message = "The region must be a valid AWS region name (e.g., us-east-1, eu-west-1)."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to all resources"

  validation {
    condition     = trimspace(lookup(var.tags, "Environment", "")) != ""
    error_message = "tags must include a non-empty Environment value."
  }
}

# Backup Vault Variables
variable "kms_key_arn" {
  type        = string
  description = "KMS key ARN for backup vault encryption"
  default     = null
}

variable "enable_vault_lock" {
  type        = bool
  description = "Enable backup vault lock for compliance"
  default     = false
}

variable "vault_lock_changeable_days" {
  type        = number
  description = "Number of days before the lock becomes immutable"
  default     = 3

  validation {
    condition     = var.vault_lock_changeable_days != null ? (var.vault_lock_changeable_days >= 3 && var.vault_lock_changeable_days <= 36500 && var.vault_lock_changeable_days == floor(var.vault_lock_changeable_days)) : false
    error_message = "vault_lock_changeable_days must not be null (a null lock input would change the lock mode or drop a bound) and must be a whole number of days, from 3 to 36500 (the AWS Backup range for ChangeableForDays)."
  }
}

variable "vault_lock_min_retention_days" {
  type        = number
  description = "Minimum retention days for locked backups"
  default     = 7

  validation {
    condition     = var.vault_lock_min_retention_days != null ? (var.vault_lock_min_retention_days >= 1 && var.vault_lock_min_retention_days <= 36500 && var.vault_lock_min_retention_days == floor(var.vault_lock_min_retention_days)) : false
    error_message = "vault_lock_min_retention_days must not be null (a null lock input would change the lock mode or drop a bound) and must be a whole number of days from 1 to 36500."
  }
}

variable "vault_lock_max_retention_days" {
  type        = number
  description = "Maximum retention days for locked backups"
  default     = 365

  validation {
    condition     = var.vault_lock_max_retention_days != null ? (var.vault_lock_max_retention_days == floor(var.vault_lock_max_retention_days) && var.vault_lock_max_retention_days <= 36500 && (var.vault_lock_min_retention_days == null || var.vault_lock_max_retention_days >= var.vault_lock_min_retention_days)) : false
    error_message = "vault_lock_max_retention_days must not be null (a null lock input would change the lock mode or drop a bound) and must be a whole number of days, at most 36500 and no smaller than vault_lock_min_retention_days."
  }
}

# Cross-Region Backup Variables
variable "enable_cross_region_backup" {
  type        = bool
  description = "Enable cross-region backup replication"
  default     = false
}

variable "replica_region" {
  type        = string
  description = "Replica region for cross-region backups (required when enable_cross_region_backup is true)"
  default     = null

  validation {
    condition     = !var.enable_cross_region_backup || (var.replica_region != null && var.replica_region != var.region)
    error_message = "replica_region must be set, and differ from region, when enable_cross_region_backup is true."
  }
}

variable "replica_kms_key_arn" {
  type        = string
  description = "KMS key ARN in replica region"
  default     = null
}

# Backup Schedule Variables
variable "daily_backup_schedule" {
  type        = string
  description = "Cron expression for daily backups"
  default     = "cron(0 2 * * ? *)" # 2 AM UTC daily
}

variable "weekly_backup_schedule" {
  type        = string
  description = "Cron expression for weekly backups"
  default     = "cron(0 3 ? * SUN *)" # 3 AM UTC Sunday
}

variable "monthly_backup_schedule" {
  type        = string
  description = "Cron expression for monthly backups"
  default     = "cron(0 4 1 * ? *)" # 4 AM UTC on 1st of month
}

variable "backup_start_window" {
  type        = number
  description = "Backup start window in minutes"
  default     = 60
}

variable "backup_completion_window" {
  type        = number
  description = "Backup completion window in minutes"
  default     = 480 # 8 hours
}

# Retention Policy Variables
variable "daily_retention_days" {
  type        = number
  description = "Retention period for daily backups in days"
  default     = 7
  nullable    = false

  validation {
    condition     = var.daily_retention_days >= 1 && var.daily_retention_days == floor(var.daily_retention_days) && var.daily_retention_days <= 36500
    error_message = "daily_retention_days must be a whole number of days from 1 to 36500."
  }
}

variable "daily_cold_storage_days" {
  type        = number
  description = "Days until daily backups move to cold storage"
  default     = null

  validation {
    condition     = var.daily_cold_storage_days == null || (var.daily_cold_storage_days >= 1 && var.daily_cold_storage_days == floor(var.daily_cold_storage_days))
    error_message = "daily_cold_storage_days must be null (no cold storage transition) or a positive whole number of days."
  }
}

variable "weekly_retention_days" {
  type        = number
  description = "Retention period for weekly backups in days"
  default     = 30
  nullable    = false

  validation {
    condition     = var.weekly_retention_days >= 1 && var.weekly_retention_days == floor(var.weekly_retention_days) && var.weekly_retention_days <= 36500
    error_message = "weekly_retention_days must be a whole number of days from 1 to 36500."
  }
}

variable "weekly_cold_storage_days" {
  type        = number
  description = "Days until weekly backups move to cold storage"
  default     = null

  validation {
    condition     = var.weekly_cold_storage_days == null || (var.weekly_cold_storage_days >= 1 && var.weekly_cold_storage_days == floor(var.weekly_cold_storage_days))
    error_message = "weekly_cold_storage_days must be null (no cold storage transition) or a positive whole number of days."
  }
}

variable "monthly_retention_days" {
  type        = number
  description = "Retention period for monthly backups in days"
  default     = 365
  nullable    = false

  validation {
    condition     = var.monthly_retention_days >= 1 && var.monthly_retention_days == floor(var.monthly_retention_days) && var.monthly_retention_days <= 36500
    error_message = "monthly_retention_days must be a whole number of days from 1 to 36500."
  }
}

variable "monthly_cold_storage_days" {
  type        = number
  description = "Days until monthly backups move to cold storage"
  # Off (null) by default, matching daily_cold_storage_days/weekly_cold_storage_days
  # above and cloudposse/terraform-aws-backup's model (rules[].lifecycle.cold_storage_after
  # is unset/null unless a caller opts in). AWS Backup requires
  # delete_after >= cold_storage_after + 90 (a recovery point must sit in cold
  # storage at least 90 days before it can be deleted), so a non-null default
  # here would only be valid for a long enough retention -- it is each
  # instance's decision, not this component's, whether its monthly retention
  # is long enough to turn cold storage on (see the lifecycle.precondition
  # below and stacks/catalog/backup/defaults.yaml).
  default = null

  validation {
    condition     = var.monthly_cold_storage_days == null || (var.monthly_cold_storage_days >= 1 && var.monthly_cold_storage_days == floor(var.monthly_cold_storage_days))
    error_message = "monthly_cold_storage_days must be null (no cold storage transition) or a positive whole number of days."
  }
}

variable "enable_archive_tier" {
  type        = bool
  description = "Enable automatic archiving for supported resources"
  default     = false
}

# Resource Selection Variables
variable "rds_instances" {
  type        = list(string)
  description = "List of RDS instance identifiers to backup, selected by ARN. Prefer enable_rds_backup (tag-based) when the RDS instance is deployed in the same Atmos deploy phase as this component: reading its state (to build this list) is rejected by workflows/scripts/common/check-deploy-layers.py"
  default     = []
}

variable "enable_rds_backup" {
  type        = bool
  description = "Enable RDS instance backups based on tags (an RDS-scoped ARN pattern, AND-conditioned on Backup=true and Environment=var.tags[\"Environment\"]) instead of an explicit rds_instances ARN list"
  default     = false
}

variable "dynamodb_tables" {
  type        = list(string)
  description = "List of DynamoDB table names to backup"
  default     = []
}

variable "efs_file_systems" {
  type        = list(string)
  description = "List of EFS file system IDs to backup"
  default     = []
}

variable "enable_ec2_backup" {
  type        = bool
  description = "Enable EC2 instance backups based on tags (an EC2-instance-scoped ARN pattern, AND-conditioned on Backup=true and Environment=var.tags[\"Environment\"])"
  default     = false
}

variable "enable_ebs_backup" {
  type        = bool
  description = "Enable EBS volume backups based on tags (an EBS-volume-scoped ARN pattern, AND-conditioned on Backup=true and Environment=var.tags[\"Environment\"]); see ebs_volume_ids for an explicit-ARN-list alternative"
  default     = false
}

variable "ebs_volume_ids" {
  type        = list(string)
  description = "List of EBS volume IDs to backup by explicit ARN, independent of enable_ebs_backup's tag-based selection"
  default     = []
}

# Notification Variables
variable "enable_backup_notifications" {
  type        = bool
  description = "Enable SNS notifications for backup events"
  default     = true
}

variable "notification_emails" {
  type        = list(string)
  description = "Email addresses for backup notifications"
  default     = []
}

variable "backup_vault_events" {
  type        = list(string)
  description = "Backup vault events to notify on"
  default = [
    "BACKUP_JOB_STARTED",
    "BACKUP_JOB_COMPLETED",
    "BACKUP_JOB_FAILED",
    "RESTORE_JOB_STARTED",
    "RESTORE_JOB_COMPLETED",
    "RESTORE_JOB_FAILED",
    "COPY_JOB_FAILED",
    "RECOVERY_POINT_MODIFIED"
  ]
}

# Reporting Variables
variable "enable_backup_reports" {
  type        = bool
  description = "Enable AWS Backup reporting"
  default     = false
}

variable "backup_reports_bucket" {
  type        = string
  description = "S3 bucket for backup reports"
  default     = null
}

variable "organization_units" {
  type        = list(string)
  description = "Organization units to include in reports"
  default     = []
}

# Backup Testing Variables
variable "enable_backup_testing" {
  type        = bool
  description = "Enable automated backup testing"
  default     = false
}

variable "backup_testing_schedule" {
  type        = string
  description = "Schedule for automated backup testing"
  default     = "cron(0 5 ? * MON *)" # 5 AM UTC Monday
}

variable "backup_testing_resource_type" {
  type        = string
  description = "AWS Backup resource type the restore-test Lambda (lambda/backup_testing.py) restores, tags, validates and deletes"
  default     = "EBS"

  validation {
    condition     = contains(["EBS", "RDS"], var.backup_testing_resource_type)
    error_message = "backup_testing_resource_type must be EBS or RDS (the two types lambda/backup_testing.py implements)."
  }
}

variable "log_retention_days" {
  type        = number
  description = "Retention in days for the restore-test Lambda's CloudWatch log group"
  default     = 365

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a CloudWatch Logs retention value (1, 3, 5, 7, 14, 30, 60, 90, ...)."
  }
}
