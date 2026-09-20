# Cost Optimization Module Variables

variable "namespace" {
  type        = string
  description = "Namespace for resource naming"

  validation {
    condition     = length(var.namespace) > 2 && length(var.namespace) < 20
    error_message = "Namespace must be between 3 and 19 characters."
  }
}

variable "environment" {
  type        = string
  description = "Environment name (dev, staging, prod)"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "stage" {
  type        = string
  description = "Stage/instance of the environment"
  default     = "default"
}

variable "region" {
  type        = string
  description = "AWS region"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-\\d+$", var.region))
    error_message = "Must be a valid AWS region."
  }
}

variable "cost_center" {
  type        = string
  description = "Cost center for billing allocation"
  default     = "engineering"
}

variable "tags" {
  type        = map(string)
  description = "Additional tags to apply to resources"
  default     = {}
}

# Budget Configuration
variable "monthly_budget_limit" {
  type        = string
  description = "Monthly budget limit in USD"
  default     = "5000"

  validation {
    condition     = can(regex("^[0-9]+$", var.monthly_budget_limit))
    error_message = "Budget limit must be a numeric string."
  }
}

variable "budget_notification_emails" {
  type        = list(string)
  description = "Email addresses for budget notifications"
  default     = []

  validation {
    condition = alltrue([
      for email in var.budget_notification_emails :
      can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))
    ])
    error_message = "All notification emails must be valid email addresses."
  }
}

# Cost Anomaly Configuration
variable "cost_anomaly_notification_email" {
  type        = string
  description = "Email address for cost anomaly notifications"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.cost_anomaly_notification_email))
    error_message = "Must be a valid email address."
  }
}

variable "cost_alert_emails" {
  type        = list(string)
  description = "Email addresses for general cost alerts"
  default     = []

  validation {
    condition = alltrue([
      for email in var.cost_alert_emails :
      can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))
    ])
    error_message = "All alert emails must be valid email addresses."
  }
}

# Cleanup Configuration
variable "cleanup_dry_run" {
  type        = string
  description = "Run cleanup in dry-run mode (true/false)"
  default     = "true"

  validation {
    condition     = contains(["true", "false"], var.cleanup_dry_run)
    error_message = "cleanup_dry_run must be 'true' or 'false'."
  }
}

variable "cleanup_unused_volumes" {
  type        = bool
  description = "Enable cleanup of unused EBS volumes"
  default     = true
}

variable "cleanup_old_snapshots" {
  type        = bool
  description = "Enable cleanup of old EBS snapshots"
  default     = true
}

variable "cleanup_unused_eips" {
  type        = bool
  description = "Enable cleanup of unused Elastic IPs"
  default     = true
}

variable "snapshot_retention_days" {
  type        = number
  description = "Number of days to retain snapshots before cleanup"
  default     = 30

  validation {
    condition     = var.snapshot_retention_days >= 7 && var.snapshot_retention_days <= 365
    error_message = "Snapshot retention must be between 7 and 365 days."
  }
}

variable "scale_down_threshold" {
  type        = number
  description = "CPU utilization threshold for scaling down (%)"
  default     = 20

  validation {
    condition     = var.scale_down_threshold >= 5 && var.scale_down_threshold <= 50
    error_message = "Scale down threshold must be between 5 and 50."
  }
}

variable "scale_up_threshold" {
  type        = number
  description = "CPU utilization threshold for scaling up (%)"
  default     = 70

  validation {
    condition     = var.scale_up_threshold >= 50 && var.scale_up_threshold <= 95
    error_message = "Scale up threshold must be between 50 and 95."
  }
}

variable "s3_ia_transition_days" {
  type        = number
  description = "Days before transitioning to Infrequent Access storage"
  default     = 30

  validation {
    condition     = var.s3_ia_transition_days >= 30 && var.s3_ia_transition_days <= 180
    error_message = "IA transition must be between 30 and 180 days."
  }
}

variable "s3_glacier_transition_days" {
  type        = number
  description = "Days before transitioning to Glacier storage"
  default     = 90

  validation {
    condition     = var.s3_glacier_transition_days >= 90 && var.s3_glacier_transition_days <= 365
    error_message = "Glacier transition must be between 90 and 365 days."
  }
}

variable "rds_backup_retention_period" {
  type        = number
  description = "RDS backup retention period in days"
  default     = 7

  validation {
    condition     = var.rds_backup_retention_period >= 1 && var.rds_backup_retention_period <= 35
    error_message = "Backup retention must be between 1 and 35 days."
  }
}
