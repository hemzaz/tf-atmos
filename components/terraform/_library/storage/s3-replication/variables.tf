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

variable "source_bucket_id" {
  description = "ID of the source S3 bucket"
  type        = string
}

variable "destination_bucket_id" {
  description = "ID of the destination S3 bucket"
  type        = string
}

variable "destination_region" {
  description = "AWS region of the destination bucket"
  type        = string
}

variable "destination_account_id" {
  description = "AWS account ID of the destination bucket (for cross-account replication)"
  type        = string
  default     = null
}

variable "enable_kms_encryption" {
  description = "Enable KMS encryption for replicated objects"
  type        = bool
  default     = false
}

variable "source_kms_key_arn" {
  description = "ARN of the KMS key used by the source bucket (required if enable_kms_encryption is true)"
  type        = string
  default     = null
}

variable "destination_kms_key_arn" {
  description = "ARN of the KMS key to use for the destination bucket (required if enable_kms_encryption is true)"
  type        = string
  default     = null
}

variable "replication_rules" {
  description = "List of replication rules"
  type = list(object({
    id                                  = string
    priority                            = number
    filter_prefix                       = optional(string)
    filter_tags                         = optional(map(string))
    destination_storage_class           = optional(string)
    delete_marker_replication_status    = optional(string)
    enable_replication_time_control     = optional(bool)
    replication_time_minutes            = optional(number)
    enable_metrics                      = optional(bool)
    metrics_event_threshold_minutes     = optional(number)
    enable_replica_modifications        = optional(bool)
  }))

  validation {
    condition     = length(var.replication_rules) > 0
    error_message = "At least one replication rule must be provided."
  }

  validation {
    condition = alltrue([
      for rule in var.replication_rules :
      rule.destination_storage_class == null || contains([
        "STANDARD", "REDUCED_REDUNDANCY", "STANDARD_IA",
        "ONEZONE_IA", "INTELLIGENT_TIERING", "GLACIER",
        "DEEP_ARCHIVE", "GLACIER_IR"
      ], rule.destination_storage_class)
    ])
    error_message = "Destination storage class must be a valid S3 storage class."
  }

  validation {
    condition = alltrue([
      for rule in var.replication_rules :
      rule.delete_marker_replication_status == null || contains(["Enabled", "Disabled"], rule.delete_marker_replication_status)
    ])
    error_message = "Delete marker replication status must be Enabled or Disabled."
  }

  default = [
    {
      id                              = "replicate-all"
      priority                        = 1
      destination_storage_class       = "STANDARD"
      enable_replication_time_control = false
      enable_metrics                  = true
    }
  ]
}

variable "enable_object_lock" {
  description = "Enable object lock on source bucket"
  type        = bool
  default     = false
}

variable "object_lock_mode" {
  description = "Object lock mode (GOVERNANCE or COMPLIANCE)"
  type        = string
  default     = "GOVERNANCE"

  validation {
    condition     = contains(["GOVERNANCE", "COMPLIANCE"], var.object_lock_mode)
    error_message = "Object lock mode must be GOVERNANCE or COMPLIANCE."
  }
}

variable "object_lock_days" {
  description = "Number of days for object lock retention"
  type        = number
  default     = 1
}

variable "enable_cloudwatch_alarms" {
  description = "Enable CloudWatch alarms for replication monitoring"
  type        = bool
  default     = true
}

variable "replication_latency_threshold_seconds" {
  description = "Threshold for replication latency alarm (seconds)"
  type        = number
  default     = 900 # 15 minutes
}

variable "bytes_pending_replication_threshold" {
  description = "Threshold for bytes pending replication alarm (bytes)"
  type        = number
  default     = 1073741824 # 1 GB
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
