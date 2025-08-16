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

# Spot Instance Configuration
variable "enable_spot_instances" {
  type        = bool
  description = "Enable spot instance usage for cost optimization"
  default     = true
}

variable "spot_max_price_percentage" {
  type        = number
  description = "Maximum spot price as percentage of on-demand price"
  default     = 80

  validation {
    condition     = var.spot_max_price_percentage > 0 && var.spot_max_price_percentage <= 100
    error_message = "Spot max price percentage must be between 1 and 100."
  }
}

variable "spot_instance_types" {
  type        = list(string)
  description = "List of instance types to use for spot instances"
  default = [
    "t3.micro",
    "t3.small",
    "t3.medium",
    "t3a.micro",
    "t3a.small",
    "t3a.medium"
  ]
}

# Reserved Instance Configuration
variable "enable_reserved_instances" {
  type        = bool
  description = "Enable reserved instance recommendations"
  default     = false
}

variable "ri_term_years" {
  type        = number
  description = "Reserved instance term in years (1 or 3)"
  default     = 1

  validation {
    condition     = contains([1, 3], var.ri_term_years)
    error_message = "RI term must be 1 or 3 years."
  }
}

variable "ri_payment_option" {
  type        = string
  description = "Reserved instance payment option"
  default     = "PARTIAL_UPFRONT"

  validation {
    condition     = contains(["ALL_UPFRONT", "PARTIAL_UPFRONT", "NO_UPFRONT"], var.ri_payment_option)
    error_message = "Payment option must be ALL_UPFRONT, PARTIAL_UPFRONT, or NO_UPFRONT."
  }
}

# Savings Plans Configuration
variable "enable_savings_plans" {
  type        = bool
  description = "Enable savings plans recommendations"
  default     = false
}

variable "sp_type" {
  type        = string
  description = "Savings plan type"
  default     = "COMPUTE_SP"

  validation {
    condition     = contains(["COMPUTE_SP", "EC2_INSTANCE_SP", "SAGEMAKER_SP"], var.sp_type)
    error_message = "Savings plan type must be COMPUTE_SP, EC2_INSTANCE_SP, or SAGEMAKER_SP."
  }
}

variable "sp_term_years" {
  type        = number
  description = "Savings plan term in years (1 or 3)"
  default     = 1

  validation {
    condition     = contains([1, 3], var.sp_term_years)
    error_message = "SP term must be 1 or 3 years."
  }
}

# Auto-scaling Configuration
variable "enable_auto_scaling" {
  type        = bool
  description = "Enable auto-scaling for cost optimization"
  default     = true
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

# Schedule Configuration
variable "enable_scheduled_scaling" {
  type        = bool
  description = "Enable scheduled scaling for predictable workloads"
  default     = true
}

variable "business_hours_start" {
  type        = string
  description = "Business hours start time (24-hour format)"
  default     = "07:00"

  validation {
    condition     = can(regex("^([01]?[0-9]|2[0-3]):[0-5][0-9]$", var.business_hours_start))
    error_message = "Start time must be in HH:MM format."
  }
}

variable "business_hours_end" {
  type        = string
  description = "Business hours end time (24-hour format)"
  default     = "19:00"

  validation {
    condition     = can(regex("^([01]?[0-9]|2[0-3]):[0-5][0-9]$", var.business_hours_end))
    error_message = "End time must be in HH:MM format."
  }
}

variable "weekend_shutdown" {
  type        = bool
  description = "Shutdown resources during weekends"
  default     = true
}

# Monitoring Configuration
variable "enable_cost_monitoring" {
  type        = bool
  description = "Enable detailed cost monitoring and reporting"
  default     = true
}

variable "cost_report_frequency" {
  type        = string
  description = "Frequency of cost reports (DAILY, WEEKLY, MONTHLY)"
  default     = "WEEKLY"

  validation {
    condition     = contains(["DAILY", "WEEKLY", "MONTHLY"], var.cost_report_frequency)
    error_message = "Report frequency must be DAILY, WEEKLY, or MONTHLY."
  }
}

variable "enable_recommendations" {
  type        = bool
  description = "Enable automated cost optimization recommendations"
  default     = true
}

# S3 Lifecycle Configuration
variable "enable_s3_lifecycle" {
  type        = bool
  description = "Enable S3 lifecycle policies for cost optimization"
  default     = true
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

variable "s3_expiration_days" {
  type        = number
  description = "Days before object expiration (0 to disable)"
  default     = 365

  validation {
    condition     = var.s3_expiration_days == 0 || (var.s3_expiration_days >= 180 && var.s3_expiration_days <= 3650)
    error_message = "Expiration must be 0 (disabled) or between 180 and 3650 days."
  }
}

# Database Optimization
variable "enable_rds_optimization" {
  type        = bool
  description = "Enable RDS cost optimization features"
  default     = true
}

variable "rds_auto_minor_version_upgrade" {
  type        = bool
  description = "Enable automatic minor version upgrades for RDS"
  default     = true
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

variable "enable_aurora_serverless" {
  type        = bool
  description = "Use Aurora Serverless for variable workloads"
  default     = false
}

variable "aurora_min_capacity" {
  type        = number
  description = "Minimum Aurora Serverless v2 capacity units"
  default     = 0.5

  validation {
    condition     = var.aurora_min_capacity >= 0.5 && var.aurora_min_capacity <= 16
    error_message = "Aurora min capacity must be between 0.5 and 16."
  }
}

variable "aurora_max_capacity" {
  type        = number
  description = "Maximum Aurora Serverless v2 capacity units"
  default     = 4

  validation {
    condition     = var.aurora_max_capacity >= 1 && var.aurora_max_capacity <= 128
    error_message = "Aurora max capacity must be between 1 and 128."
  }
}