variable "name_prefix" {
  type        = string
  description = "Prefix for resource names"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.name_prefix))
    error_message = "Name prefix must contain only alphanumeric characters and hyphens."
  }
}

variable "log_retention_days" {
  type        = number
  description = "Default log retention period in days"
  default     = 30

  validation {
    condition     = contains([0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Invalid retention period. Must be a valid CloudWatch Logs retention value."
  }
}

variable "kms_key_id" {
  type        = string
  description = "KMS key ID for encryption"
  default     = null
}

variable "service_log_groups" {
  type = map(object({
    retention_days = optional(number)
    filter_pattern = optional(string)
  }))
  description = "Map of service names to log group configurations"
  default     = {}
}

# Kinesis Streaming
variable "enable_kinesis_streaming" {
  type        = bool
  description = "Enable log streaming to Kinesis"
  default     = true
}

variable "kinesis_shard_count" {
  type        = number
  description = "Number of Kinesis shards"
  default     = 1

  validation {
    condition     = var.kinesis_shard_count >= 1
    error_message = "Shard count must be at least 1."
  }
}

variable "kinesis_retention_hours" {
  type        = number
  description = "Kinesis data retention in hours"
  default     = 24

  validation {
    condition     = var.kinesis_retention_hours >= 24 && var.kinesis_retention_hours <= 8760
    error_message = "Retention must be between 24 and 8760 hours."
  }
}

variable "kinesis_on_demand" {
  type        = bool
  description = "Use Kinesis on-demand mode"
  default     = false
}

# S3 Export
variable "enable_s3_export" {
  type        = bool
  description = "Enable log export to S3"
  default     = true
}

variable "s3_transition_to_ia_days" {
  type        = number
  description = "Days before transitioning to IA storage"
  default     = 90

  validation {
    condition     = var.s3_transition_to_ia_days >= 30
    error_message = "Transition to IA must be at least 30 days."
  }
}

variable "s3_transition_to_glacier_days" {
  type        = number
  description = "Days before transitioning to Glacier"
  default     = 180

  validation {
    condition     = var.s3_transition_to_glacier_days >= 90
    error_message = "Transition to Glacier must be at least 90 days."
  }
}

variable "s3_expiration_days" {
  type        = number
  description = "Days before log expiration"
  default     = 365

  validation {
    condition     = var.s3_expiration_days >= 1
    error_message = "Expiration must be at least 1 day."
  }
}

variable "export_schedule" {
  type        = string
  description = "CloudWatch Events schedule expression for exports"
  default     = "cron(0 2 * * ? *)" # 2 AM daily

  validation {
    condition     = can(regex("^(rate|cron)\\(.+\\)$", var.export_schedule))
    error_message = "Schedule must be a valid rate or cron expression."
  }
}

# Athena Queries
variable "enable_athena_queries" {
  type        = bool
  description = "Enable Athena query setup"
  default     = true
}

# Metric Filters
variable "create_error_metric_filter" {
  type        = bool
  description = "Create error count metric filter"
  default     = true
}

variable "error_filter_pattern" {
  type        = string
  description = "Pattern for error log filtering"
  default     = "[ERROR]"
}

variable "custom_metric_namespace" {
  type        = string
  description = "CloudWatch namespace for custom metrics"
  default     = "Custom/Logs"

  validation {
    condition     = can(regex("^[a-zA-Z0-9/_-]+$", var.custom_metric_namespace))
    error_message = "Namespace must contain only alphanumeric characters, forward slashes, underscores, and hyphens."
  }
}

variable "custom_metric_filters" {
  type = map(object({
    pattern     = string
    metric_name = string
    value       = string
    unit        = optional(string)
  }))
  description = "Custom metric filter configurations"
  default     = {}
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to resources"
  default     = {}
}
