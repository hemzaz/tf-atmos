variable "name_prefix" {
  type        = string
  description = "Prefix for resource names"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.name_prefix))
    error_message = "Name prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "stream_mode" {
  type        = string
  description = "Stream capacity mode (PROVISIONED or ON_DEMAND)"
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["PROVISIONED", "ON_DEMAND"], var.stream_mode)
    error_message = "Stream mode must be PROVISIONED or ON_DEMAND."
  }
}

variable "shard_count" {
  type        = number
  description = "Number of shards (for PROVISIONED mode)"
  default     = 1

  validation {
    condition     = var.shard_count >= 1 && var.shard_count <= 500
    error_message = "Shard count must be between 1 and 500."
  }
}

variable "retention_hours" {
  type        = number
  description = "Data retention period in hours (24-8760)"
  default     = 24

  validation {
    condition     = var.retention_hours >= 24 && var.retention_hours <= 8760
    error_message = "Retention must be between 24 and 8760 hours."
  }
}

variable "kms_key_id" {
  type        = string
  description = "KMS key ID for encryption (null for no encryption)"
  default     = null
}

variable "enable_enhanced_monitoring" {
  type        = bool
  description = "Enable enhanced shard-level metrics"
  default     = true
}

variable "enhanced_fanout_consumers" {
  type        = set(string)
  description = "Set of enhanced fan-out consumer names"
  default     = []
}

variable "lambda_consumers" {
  type = map(object({
    function_name          = string
    starting_position      = optional(string, "LATEST")
    batch_size             = optional(number, 100)
    batching_window        = optional(number, 0)
    parallelization_factor = optional(number, 1)
    enabled                = optional(bool, true)
    on_failure_destination = optional(string, null)
    filter_pattern         = optional(string, null)
  }))
  description = "Map of Lambda consumer configurations"
  default     = {}
}

variable "enable_cloudwatch_logs" {
  type        = bool
  description = "Enable CloudWatch Logs"
  default     = false
}

variable "log_retention_days" {
  type        = number
  description = "CloudWatch log retention in days"
  default     = 7

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Invalid log retention period."
  }
}

variable "enable_monitoring" {
  type        = bool
  description = "Enable CloudWatch alarms"
  default     = true
}

variable "iterator_age_threshold_ms" {
  type        = number
  description = "Iterator age alarm threshold in milliseconds"
  default     = 60000

  validation {
    condition     = var.iterator_age_threshold_ms > 0
    error_message = "Iterator age threshold must be positive."
  }
}

variable "alarm_actions" {
  type        = list(string)
  description = "List of ARNs for alarm actions (SNS topics)"
  default     = []
}

variable "enable_auto_scaling" {
  type        = bool
  description = "Enable auto-scaling for provisioned mode"
  default     = false
}

variable "min_shard_count" {
  type        = number
  description = "Minimum shard count for auto-scaling"
  default     = 1

  validation {
    condition     = var.min_shard_count >= 1
    error_message = "Minimum shard count must be at least 1."
  }
}

variable "max_shard_count" {
  type        = number
  description = "Maximum shard count for auto-scaling"
  default     = 10

  validation {
    condition     = var.max_shard_count >= 1 && var.max_shard_count <= 500
    error_message = "Maximum shard count must be between 1 and 500."
  }
}

variable "scaling_target_utilization" {
  type        = number
  description = "Target utilization percentage for auto-scaling"
  default     = 70

  validation {
    condition     = var.scaling_target_utilization > 0 && var.scaling_target_utilization <= 100
    error_message = "Target utilization must be between 0 and 100."
  }
}

variable "tags" {
  type        = map(string)
  description = "Additional tags for all resources"
  default     = {}
}
