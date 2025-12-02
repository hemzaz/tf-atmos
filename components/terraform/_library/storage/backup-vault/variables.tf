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

variable "kms_key_id" {
  description = "KMS key ID for backup vault encryption (if null, a new key will be created)"
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

variable "enable_vault_lock" {
  description = "Enable vault lock for compliance (prevents deletion of backups)"
  type        = bool
  default     = false
}

variable "vault_lock_changeable_days" {
  description = "Number of days before vault lock becomes immutable"
  type        = number
  default     = 3

  validation {
    condition     = var.vault_lock_changeable_days >= 0
    error_message = "Vault lock changeable days must be non-negative."
  }
}

variable "vault_lock_max_retention_days" {
  description = "Maximum retention period in days for recovery points"
  type        = number
  default     = 365

  validation {
    condition     = var.vault_lock_max_retention_days > 0
    error_message = "Vault lock max retention days must be positive."
  }
}

variable "vault_lock_min_retention_days" {
  description = "Minimum retention period in days for recovery points"
  type        = number
  default     = 7

  validation {
    condition     = var.vault_lock_min_retention_days > 0
    error_message = "Vault lock min retention days must be positive."
  }
}

variable "vault_policy" {
  description = "Vault access policy (JSON string)"
  type        = string
  default     = null
}

variable "enable_notifications" {
  description = "Enable SNS notifications for backup events"
  type        = bool
  default     = true
}

variable "notification_endpoints" {
  description = "List of email addresses for backup notifications"
  type        = list(string)
  default     = []
}

variable "notification_events" {
  description = "List of backup vault events to notify on"
  type        = list(string)
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

variable "backup_plans" {
  description = "Map of backup plans to create"
  type = map(object({
    rules = list(object({
      name                     = string
      schedule                 = string
      start_window             = optional(number)
      completion_window        = optional(number)
      enable_continuous_backup = optional(bool)
      lifecycle = object({
        delete_after       = optional(number)
        cold_storage_after = optional(number)
      })
      copy_actions = optional(list(object({
        destination_vault_arn = string
        lifecycle = object({
          delete_after       = optional(number)
          cold_storage_after = optional(number)
        })
      })))
      recovery_point_tags = optional(map(string))
    }))
    selection_tags = optional(list(object({
      key   = string
      value = string
    })))
    resource_arns = optional(list(string))
    conditions = optional(list(object({
      string_equals = optional(list(object({
        key   = string
        value = string
      })))
      string_like = optional(list(object({
        key   = string
        value = string
      })))
      string_not_equals = optional(list(object({
        key   = string
        value = string
      })))
      string_not_like = optional(list(object({
        key   = string
        value = string
      })))
    })))
    advanced_backup_settings = optional(list(object({
      resource_type  = string
      backup_options = map(string)
    })))
  }))

  default = {
    daily = {
      rules = [
        {
          name     = "daily-backup"
          schedule = "cron(0 5 * * ? *)"
          lifecycle = {
            delete_after       = 35
            cold_storage_after = 30
          }
        }
      ]
      selection_tags = [
        {
          key   = "Backup"
          value = "daily"
        }
      ]
    }
  }
}

variable "enable_cloudwatch_alarms" {
  description = "Enable CloudWatch alarms for backup monitoring"
  type        = bool
  default     = true
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
