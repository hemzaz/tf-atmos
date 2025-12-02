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

variable "subnet_ids" {
  description = "List of subnet IDs for EFS mount targets (one per AZ)"
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) > 0
    error_message = "At least one subnet ID must be provided."
  }
}

variable "security_group_ids" {
  description = "List of security group IDs for EFS mount targets"
  type        = list(string)

  validation {
    condition     = length(var.security_group_ids) > 0
    error_message = "At least one security group ID must be provided."
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

variable "performance_mode" {
  description = "Performance mode (generalPurpose or maxIO)"
  type        = string
  default     = "generalPurpose"

  validation {
    condition     = contains(["generalPurpose", "maxIO"], var.performance_mode)
    error_message = "Performance mode must be generalPurpose or maxIO."
  }
}

variable "throughput_mode" {
  description = "Throughput mode (bursting, provisioned, or elastic)"
  type        = string
  default     = "bursting"

  validation {
    condition     = contains(["bursting", "provisioned", "elastic"], var.throughput_mode)
    error_message = "Throughput mode must be bursting, provisioned, or elastic."
  }
}

variable "provisioned_throughput_in_mibps" {
  description = "Provisioned throughput in MiB/s (required if throughput_mode is provisioned)"
  type        = number
  default     = null

  validation {
    condition     = var.provisioned_throughput_in_mibps == null || (var.provisioned_throughput_in_mibps >= 1 && var.provisioned_throughput_in_mibps <= 1024)
    error_message = "Provisioned throughput must be between 1 and 1024 MiB/s."
  }
}

variable "transition_to_ia" {
  description = "Lifecycle policy to transition files to Infrequent Access (AFTER_7_DAYS, AFTER_14_DAYS, AFTER_30_DAYS, AFTER_60_DAYS, AFTER_90_DAYS, or null to disable)"
  type        = string
  default     = "AFTER_30_DAYS"

  validation {
    condition = var.transition_to_ia == null || contains([
      "AFTER_7_DAYS", "AFTER_14_DAYS", "AFTER_30_DAYS",
      "AFTER_60_DAYS", "AFTER_90_DAYS"
    ], var.transition_to_ia)
    error_message = "Transition to IA must be a valid lifecycle policy value."
  }
}

variable "transition_to_archive" {
  description = "Lifecycle policy to transition files to Archive (AFTER_1_DAY through AFTER_90_DAYS, or null to disable)"
  type        = string
  default     = null

  validation {
    condition = var.transition_to_archive == null || can(regex("^AFTER_([1-9]|[1-9][0-9])_DAYS?$", var.transition_to_archive))
    error_message = "Transition to archive must be a valid lifecycle policy value."
  }
}

variable "transition_to_primary_storage_class" {
  description = "Lifecycle policy to transition files back to primary storage (AFTER_1_ACCESS or null to disable)"
  type        = string
  default     = null

  validation {
    condition     = var.transition_to_primary_storage_class == null || var.transition_to_primary_storage_class == "AFTER_1_ACCESS"
    error_message = "Transition to primary storage class must be AFTER_1_ACCESS or null."
  }
}

variable "access_points" {
  description = "Map of EFS access points to create"
  type = map(object({
    posix_user = object({
      gid            = number
      uid            = number
      secondary_gids = optional(list(number))
    })
    root_directory = object({
      path = string
      creation_info = object({
        owner_gid   = number
        owner_uid   = number
        permissions = string
      })
    })
    tags = optional(map(string))
  }))
  default = {}
}

variable "enable_backup_policy" {
  description = "Enable automatic backups through AWS Backup"
  type        = bool
  default     = true
}

variable "file_system_policy" {
  description = "EFS file system policy (JSON string)"
  type        = string
  default     = null
}

variable "enable_cloudwatch_alarms" {
  description = "Enable CloudWatch alarms for EFS monitoring"
  type        = bool
  default     = true
}

variable "burst_credit_balance_threshold" {
  description = "Threshold for burst credit balance alarm (bytes)"
  type        = number
  default     = 192000000000 # 192 GB
}

variable "client_connections_threshold" {
  description = "Threshold for client connections alarm"
  type        = number
  default     = 500
}

variable "percent_io_limit_threshold" {
  description = "Threshold for percent IO limit alarm (%)"
  type        = number
  default     = 95
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
