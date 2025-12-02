variable "name_prefix" {
  type        = string
  description = "Prefix for resource names"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.name_prefix))
    error_message = "Name prefix must contain only alphanumeric characters and hyphens."
  }
}

variable "create_sns_topic" {
  type        = bool
  description = "Create SNS topic for alarm notifications"
  default     = true
}

variable "alarm_email_endpoints" {
  type        = list(string)
  description = "Email addresses for alarm notifications"
  default     = []

  validation {
    condition = alltrue([
      for email in var.alarm_email_endpoints : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))
    ])
    error_message = "All email addresses must be valid."
  }
}

variable "kms_key_id" {
  type        = string
  description = "KMS key ID for SNS topic encryption"
  default     = null
}

variable "alarm_actions" {
  type        = list(string)
  description = "ARNs to notify when alarm transitions to ALARM state"
  default     = []
}

variable "ok_actions" {
  type        = list(string)
  description = "ARNs to notify when alarm transitions to OK state"
  default     = []
}

# CPU Alarms
variable "create_cpu_alarms" {
  type        = bool
  description = "Create CPU utilization alarms"
  default     = true
}

variable "cpu_threshold" {
  type        = number
  description = "CPU utilization threshold percentage"
  default     = 80

  validation {
    condition     = var.cpu_threshold >= 1 && var.cpu_threshold <= 100
    error_message = "CPU threshold must be between 1 and 100."
  }
}

variable "cpu_evaluation_periods" {
  type        = number
  description = "Number of evaluation periods for CPU alarm"
  default     = 2

  validation {
    condition     = var.cpu_evaluation_periods >= 1
    error_message = "Evaluation periods must be at least 1."
  }
}

variable "cpu_period" {
  type        = number
  description = "Period in seconds for CPU metric"
  default     = 300

  validation {
    condition     = contains([60, 300, 900, 3600], var.cpu_period)
    error_message = "Period must be 60, 300, 900, or 3600 seconds."
  }
}

# Memory Alarms
variable "create_memory_alarms" {
  type        = bool
  description = "Create memory utilization alarms"
  default     = true
}

variable "memory_threshold" {
  type        = number
  description = "Memory utilization threshold percentage"
  default     = 85

  validation {
    condition     = var.memory_threshold >= 1 && var.memory_threshold <= 100
    error_message = "Memory threshold must be between 1 and 100."
  }
}

variable "memory_evaluation_periods" {
  type        = number
  description = "Number of evaluation periods for memory alarm"
  default     = 2
}

variable "memory_period" {
  type        = number
  description = "Period in seconds for memory metric"
  default     = 300
}

# Disk Alarms
variable "create_disk_alarms" {
  type        = bool
  description = "Create disk utilization alarms"
  default     = true
}

variable "disk_threshold" {
  type        = number
  description = "Disk utilization threshold percentage"
  default     = 90

  validation {
    condition     = var.disk_threshold >= 1 && var.disk_threshold <= 100
    error_message = "Disk threshold must be between 1 and 100."
  }
}

variable "disk_evaluation_periods" {
  type        = number
  description = "Number of evaluation periods for disk alarm"
  default     = 2
}

variable "disk_period" {
  type        = number
  description = "Period in seconds for disk metric"
  default     = 300
}

# Anomaly Detection
variable "enable_anomaly_detection" {
  type        = bool
  description = "Enable anomaly detection alarms"
  default     = false
}

variable "anomaly_detection_band" {
  type        = number
  description = "Standard deviations for anomaly detection band"
  default     = 2

  validation {
    condition     = var.anomaly_detection_band >= 1 && var.anomaly_detection_band <= 10
    error_message = "Anomaly detection band must be between 1 and 10."
  }
}

# Composite Alarms
variable "create_composite_alarms" {
  type        = bool
  description = "Create composite alarms for complex conditions"
  default     = false
}

# Custom Alarms
variable "custom_alarms" {
  type = map(object({
    comparison_operator = string
    evaluation_periods  = number
    metric_name         = string
    namespace           = string
    period              = number
    statistic           = string
    threshold           = number
    description         = string
    treat_missing_data  = optional(string)
    dimensions          = optional(map(string))
  }))
  description = "Custom alarm configurations"
  default     = {}
}

# Auto-Remediation
variable "enable_auto_remediation" {
  type        = bool
  description = "Enable automatic remediation with Lambda"
  default     = false
}

variable "auto_remediation_actions" {
  type        = list(string)
  description = "List of auto-remediation actions to enable"
  default     = ["restart_instance", "scale_up"]
}

variable "slack_webhook_url" {
  type        = string
  description = "Slack webhook URL for notifications"
  default     = ""
  sensitive   = true
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to resources"
  default     = {}
}
