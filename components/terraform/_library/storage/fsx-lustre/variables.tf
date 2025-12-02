variable "name_prefix" {
  description = "Name prefix for resources"
  type        = string

  validation {
    condition     = length(var.name_prefix) > 0 && length(var.name_prefix) <= 32
    error_message = "Name prefix must be between 1 and 32 characters."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, production)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "production", "test", "qa"], var.environment)
    error_message = "Environment must be one of: dev, staging, production, test, qa."
  }
}

variable "subnet_id" {
  description = "Subnet ID for FSx Lustre file system"
  type        = string
}

variable "security_group_ids" {
  description = "List of security group IDs for FSx Lustre"
  type        = list(string)

  validation {
    condition     = length(var.security_group_ids) > 0
    error_message = "At least one security group ID must be provided."
  }
}

variable "storage_capacity_gb" {
  description = "Storage capacity in GiB (1200, 2400, or increments of 2400 for SCRATCH; 1200, 2400, or increments of 2400 for PERSISTENT)"
  type        = number

  validation {
    condition     = var.storage_capacity_gb >= 1200
    error_message = "Storage capacity must be at least 1200 GiB."
  }
}

variable "deployment_type" {
  description = "Deployment type (SCRATCH_1, SCRATCH_2, PERSISTENT_1, or PERSISTENT_2)"
  type        = string
  default     = "PERSISTENT_2"

  validation {
    condition     = contains(["SCRATCH_1", "SCRATCH_2", "PERSISTENT_1", "PERSISTENT_2"], var.deployment_type)
    error_message = "Deployment type must be SCRATCH_1, SCRATCH_2, PERSISTENT_1, or PERSISTENT_2."
  }
}

variable "storage_type" {
  description = "Storage type (SSD or HDD, HDD only available for PERSISTENT_1)"
  type        = string
  default     = "SSD"

  validation {
    condition     = contains(["SSD", "HDD"], var.storage_type)
    error_message = "Storage type must be SSD or HDD."
  }
}

variable "per_unit_storage_throughput" {
  description = "Provisioned throughput per unit of storage (MB/s/TiB). Valid values: 50, 100, 200 for PERSISTENT_1; 125, 250, 500, 1000 for PERSISTENT_2"
  type        = number
  default     = 200

  validation {
    condition     = contains([50, 100, 125, 200, 250, 500, 1000], var.per_unit_storage_throughput)
    error_message = "Per unit storage throughput must be a valid value."
  }
}

variable "enable_encryption" {
  description = "Enable encryption at rest"
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "KMS key ID for encryption (if null, a new key will be created)"
  type        = string
  default     = null
}

variable "kms_deletion_window_days" {
  description = "KMS key deletion window in days"
  type        = number
  default     = 30

  validation {
    condition     = var.kms_deletion_window_days >= 7 && var.kms_deletion_window_days <= 30
    error_message = "KMS deletion window must be between 7 and 30 days."
  }
}

variable "automatic_backup_retention_days" {
  description = "Number of days to retain automatic backups (0-90, only for PERSISTENT deployments)"
  type        = number
  default     = 7

  validation {
    condition     = var.automatic_backup_retention_days >= 0 && var.automatic_backup_retention_days <= 90
    error_message = "Automatic backup retention must be between 0 and 90 days."
  }
}

variable "daily_automatic_backup_start_time" {
  description = "Daily automatic backup start time (HH:MM format, only for PERSISTENT deployments)"
  type        = string
  default     = "03:00"

  validation {
    condition     = can(regex("^([0-1][0-9]|2[0-3]):[0-5][0-9]$", var.daily_automatic_backup_start_time))
    error_message = "Daily automatic backup start time must be in HH:MM format."
  }
}

variable "copy_tags_to_backups" {
  description = "Copy tags to backups (only for PERSISTENT deployments)"
  type        = bool
  default     = true
}

variable "weekly_maintenance_start_time" {
  description = "Weekly maintenance start time (d:HH:MM format)"
  type        = string
  default     = "1:03:00"

  validation {
    condition     = can(regex("^[1-7]:([0-1][0-9]|2[0-3]):[0-5][0-9]$", var.weekly_maintenance_start_time))
    error_message = "Weekly maintenance start time must be in d:HH:MM format (d is day of week 1-7)."
  }
}

variable "data_compression_type" {
  description = "Data compression type (NONE or LZ4)"
  type        = string
  default     = "LZ4"

  validation {
    condition     = contains(["NONE", "LZ4"], var.data_compression_type)
    error_message = "Data compression type must be NONE or LZ4."
  }
}

variable "create_s3_bucket" {
  description = "Create an S3 bucket for data repository"
  type        = bool
  default     = false
}

variable "s3_force_destroy" {
  description = "Force destroy S3 bucket even if it contains objects"
  type        = bool
  default     = false
}

variable "s3_import_path" {
  description = "S3 path for importing data (s3://bucket/prefix)"
  type        = string
  default     = null
}

variable "s3_export_path" {
  description = "S3 path for exporting data (s3://bucket/prefix)"
  type        = string
  default     = null
}

variable "imported_file_chunk_size" {
  description = "Chunk size for importing files from S3 (1-512000 MiB)"
  type        = number
  default     = 1024

  validation {
    condition     = var.imported_file_chunk_size >= 1 && var.imported_file_chunk_size <= 512000
    error_message = "Imported file chunk size must be between 1 and 512000 MiB."
  }
}

variable "data_repository_associations" {
  description = "Map of data repository associations to create"
  type = map(object({
    data_repository_path             = string
    file_system_path                 = string
    batch_import_meta_data_on_create = optional(bool)
    imported_file_chunk_size         = optional(number)
    s3_auto_import_policy            = optional(list(string))
    s3_auto_export_policy            = optional(list(string))
  }))
  default = {}
}

variable "enable_logging" {
  description = "Enable CloudWatch logging"
  type        = bool
  default     = true
}

variable "log_level" {
  description = "Log level (WARN_ONLY, ERROR_ONLY, or WARN_ERROR)"
  type        = string
  default     = "WARN_ERROR"

  validation {
    condition     = contains(["WARN_ONLY", "ERROR_ONLY", "WARN_ERROR"], var.log_level)
    error_message = "Log level must be WARN_ONLY, ERROR_ONLY, or WARN_ERROR."
  }
}

variable "log_destination_arn" {
  description = "CloudWatch log group ARN (if null, a new log group will be created)"
  type        = string
  default     = null
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 7

  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180,
      365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention must be a valid CloudWatch Logs retention period."
  }
}

variable "enable_cloudwatch_alarms" {
  description = "Enable CloudWatch alarms for FSx monitoring"
  type        = bool
  default     = true
}

variable "storage_used_threshold_percent" {
  description = "Threshold percentage for storage used alarm"
  type        = number
  default     = 80

  validation {
    condition     = var.storage_used_threshold_percent > 0 && var.storage_used_threshold_percent <= 100
    error_message = "Storage used threshold must be between 0 and 100 percent."
  }
}

variable "alarm_actions" {
  description = "List of ARNs to notify when alarms trigger"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
