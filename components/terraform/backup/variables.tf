variable "region" {
  type        = string
  description = "AWS region"
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to all resources"
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
}

variable "vault_lock_min_retention_days" {
  type        = number
  description = "Minimum retention days for locked backups"
  default     = 7
}

variable "vault_lock_max_retention_days" {
  type        = number
  description = "Maximum retention days for locked backups"
  default     = 365
}

# Cross-Region Backup Variables
variable "enable_cross_region_backup" {
  type        = bool
  description = "Enable cross-region backup replication"
  default     = false
}

variable "replica_region" {
  type        = string
  description = "Replica region for cross-region backups"
  default     = null
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
}

variable "daily_cold_storage_days" {
  type        = number
  description = "Days until daily backups move to cold storage"
  default     = null
}

variable "weekly_retention_days" {
  type        = number
  description = "Retention period for weekly backups in days"
  default     = 30
}

variable "weekly_cold_storage_days" {
  type        = number
  description = "Days until weekly backups move to cold storage"
  default     = null
}

variable "monthly_retention_days" {
  type        = number
  description = "Retention period for monthly backups in days"
  default     = 365
}

variable "monthly_cold_storage_days" {
  type        = number
  description = "Days until monthly backups move to cold storage"
  default     = 90
}

variable "enable_archive_tier" {
  type        = bool
  description = "Enable automatic archiving for supported resources"
  default     = false
}

# Resource Selection Variables
variable "rds_instances" {
  type        = list(string)
  description = "List of RDS instance identifiers to backup"
  default     = []
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
  description = "Enable EC2 instance backups based on tags"
  default     = false
}

variable "enable_ebs_backup" {
  type        = bool
  description = "Enable EBS volume backups"
  default     = false
}

variable "ebs_volume_ids" {
  type        = list(string)
  description = "List of EBS volume IDs to backup"
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
