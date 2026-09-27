# Cost Optimization Module Variables

variable "region" {
  type        = string
  description = "AWS region"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-\\d+$", var.region))
    error_message = "Must be a valid AWS region."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to resources; must include Environment (used in resource names)"

  validation {
    condition     = trimspace(lookup(var.tags, "Environment", "")) != ""
    error_message = "tags must include a non-empty Environment value."
  }
}

# Cloud Posse null-label style: every resource this component creates is
# named "<tags.Environment>-<name>-<suffix>". Co-located instances of this
# component must use distinct values.
variable "name" {
  type        = string
  description = "Per-instance name, combined with tags.Environment to build every resource name (<Environment>-<name>-<suffix>)"
  default     = "main"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.name))
    error_message = "name must be non-empty, lowercase alphanumeric characters and hyphens, and must not start or end with a hyphen."
  }
}

# The lifecycle tier this component's per-stage schedule map keys off, set
# from settings.context.stage (dev/staging/prod) - NOT tags.Environment, which
# is the real per-stack environment name (e.g. testenv-01). Validated to
# exactly the map's keys, so lookup() with a default fallback is unnecessary:
# an unrecognized value fails plan instead of silently running dev settings.
variable "environment" {
  type        = string
  description = "Lifecycle tier (dev, staging or prod) that selects the per-stage schedule/auto-shutdown settings, from settings.context.stage"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "kms_key_arn" {
  type        = string
  description = "Customer managed KMS key ARN that encrypts the Lambda functions' CloudWatch log groups and the cost-alerts SNS topic. Its policy must allow logs.<region>.amazonaws.com (kms allow_cloudwatch_logs) for the log groups, and cloudwatch.amazonaws.com (kms allow_cloudwatch_alarms) so the *_errors alarms can publish to the encrypted SNS topic"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/.+$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN (arn:aws:kms:<region>:<account>:key/<id>)."
  }
}

variable "log_retention_days" {
  type        = number
  description = "Number of days to retain the Lambda functions' CloudWatch log groups"
  default     = 365

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a CloudWatch Logs retention value (1, 3, 5, 7, 14, 30, 60, 90, ...)."
  }
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
  description = "Email addresses for general cost alerts (Savings Plan/RI recommendations, resource cleanup summaries)"
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
  description = "Run cleanup in dry-run mode (true/false); dry-run only logs and publishes what would be deleted, it deletes nothing"
  default     = "true"

  validation {
    condition     = contains(["true", "false"], var.cleanup_dry_run)
    error_message = "cleanup_dry_run must be 'true' or 'false'."
  }
}

variable "cleanup_unused_volumes" {
  type        = bool
  description = "Enable cleanup of unused (available, opt-in tagged) EBS volumes"
  default     = true
}

variable "cleanup_old_snapshots" {
  type        = bool
  description = "Enable cleanup of old (opt-in tagged) EBS snapshots"
  default     = true
}

variable "cleanup_unused_eips" {
  type        = bool
  description = "Enable cleanup of unused (unassociated, opt-in tagged) Elastic IPs"
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
