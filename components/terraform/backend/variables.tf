# Core backend configuration variables
variable "tenant" {
  type        = string
  description = "Tenant name for resource naming"
  default     = "" # Will be set by Atmos
}

variable "environment" {
  type        = string
  description = "Environment name (dev, staging, prod)"
  default     = ""
  
  validation {
    condition     = contains(["", "dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "account_id" {
  type        = string
  description = "AWS Account ID for resource policies"
  default     = "" # Will be set by Atmos
  
  validation {
    condition     = var.account_id == "" || can(regex("^[0-9]{12}$", var.account_id))
    error_message = "Account ID must be a 12-digit number."
  }
}

variable "bucket_name" {
  type        = string
  description = "Name of the S3 bucket for Terraform state"
  default     = "" # Will be set by Atmos
  
  validation {
    condition     = var.bucket_name == "" || can(regex("^[a-z0-9][a-z0-9.-]*[a-z0-9]$", var.bucket_name))
    error_message = "Bucket name must be DNS compliant."
  }
}

variable "dynamodb_table_name" {
  type        = string
  description = "Name of the DynamoDB table for Terraform state locking"
  default     = "" # Will be set by Atmos
}

variable "region" {
  type        = string
  description = "AWS region"
  default     = "" # Will be set by Atmos
  
  validation {
    condition     = var.region == "" || can(regex("^[a-z]{2}(-[a-z]+)+-\\d+$", var.region))
    error_message = "Must be a valid AWS region format."
  }
}

variable "state_file_key" {
  type        = string
  description = "Key for the state file in S3 bucket"
  default     = "terraform.tfstate"
}

variable "iam_role_name" {
  type        = string
  description = "Name of the IAM role to assume for Terraform execution"
  default     = "" # Will be set by Atmos
}

variable "iam_role_arn" {
  type        = string
  description = "ARN of the IAM role to assume for Terraform execution"
  default     = "" # Will be set by Atmos
  
  validation {
    condition     = var.iam_role_arn == "" || can(regex("^arn:aws:iam::[0-9]{12}:role/", var.iam_role_arn))
    error_message = "IAM role ARN must be a valid AWS IAM role ARN."
  }
}

# DynamoDB configuration
variable "dynamodb_billing_mode" {
  type        = string
  description = "DynamoDB billing mode (PAY_PER_REQUEST or PROVISIONED)"
  default     = "PAY_PER_REQUEST"
  
  validation {
    condition     = contains(["PAY_PER_REQUEST", "PROVISIONED"], var.dynamodb_billing_mode)
    error_message = "Billing mode must be PAY_PER_REQUEST or PROVISIONED."
  }
}

variable "dynamodb_read_capacity" {
  type        = number
  description = "DynamoDB read capacity units (only used with PROVISIONED billing)"
  default     = 5
  
  validation {
    condition     = var.dynamodb_read_capacity >= 1 && var.dynamodb_read_capacity <= 40000
    error_message = "Read capacity must be between 1 and 40000."
  }
}

variable "dynamodb_write_capacity" {
  type        = number
  description = "DynamoDB write capacity units (only used with PROVISIONED billing)"
  default     = 5
  
  validation {
    condition     = var.dynamodb_write_capacity >= 1 && var.dynamodb_write_capacity <= 40000
    error_message = "Write capacity must be between 1 and 40000."
  }
}

variable "dynamodb_table_class" {
  type        = string
  description = "DynamoDB table class for cost optimization"
  default     = "STANDARD"
  
  validation {
    condition     = contains(["STANDARD", "STANDARD_INFREQUENT_ACCESS"], var.dynamodb_table_class)
    error_message = "Table class must be STANDARD or STANDARD_INFREQUENT_ACCESS."
  }
}

# Security and operational features
variable "enable_point_in_time_recovery" {
  type        = bool
  description = "Enable point-in-time recovery for DynamoDB table"
  default     = true
}

variable "enable_deletion_protection" {
  type        = bool
  description = "Enable deletion protection for DynamoDB table"
  default     = true
}

variable "enable_lock_ttl" {
  type        = bool
  description = "Enable TTL for automatic cleanup of expired locks"
  default     = true
}

variable "enable_monitoring" {
  type        = bool
  description = "Enable CloudWatch monitoring and alarms"
  default     = true
}

variable "enable_auto_scaling" {
  type        = bool
  description = "Enable auto-scaling for DynamoDB table (PROVISIONED mode only)"
  default     = false
}

# Auto-scaling configuration
variable "autoscaling_read_min_capacity" {
  type        = number
  description = "Minimum read capacity for auto-scaling"
  default     = 5
  
  validation {
    condition     = var.autoscaling_read_min_capacity >= 1 && var.autoscaling_read_min_capacity <= 40000
    error_message = "Min read capacity must be between 1 and 40000."
  }
}

variable "autoscaling_read_max_capacity" {
  type        = number
  description = "Maximum read capacity for auto-scaling"
  default     = 100
  
  validation {
    condition     = var.autoscaling_read_max_capacity >= 1 && var.autoscaling_read_max_capacity <= 40000
    error_message = "Max read capacity must be between 1 and 40000."
  }
}

variable "autoscaling_write_min_capacity" {
  type        = number
  description = "Minimum write capacity for auto-scaling"
  default     = 5
  
  validation {
    condition     = var.autoscaling_write_min_capacity >= 1 && var.autoscaling_write_min_capacity <= 40000
    error_message = "Min write capacity must be between 1 and 40000."
  }
}

variable "autoscaling_write_max_capacity" {
  type        = number
  description = "Maximum write capacity for auto-scaling"
  default     = 100
  
  validation {
    condition     = var.autoscaling_write_max_capacity >= 1 && var.autoscaling_write_max_capacity <= 40000
    error_message = "Max write capacity must be between 1 and 40000."
  }
}

variable "autoscaling_read_target_utilization" {
  type        = number
  description = "Target utilization percentage for read capacity auto-scaling"
  default     = 70
  
  validation {
    condition     = var.autoscaling_read_target_utilization >= 20 && var.autoscaling_read_target_utilization <= 90
    error_message = "Target utilization must be between 20 and 90 percent."
  }
}

variable "autoscaling_write_target_utilization" {
  type        = number
  description = "Target utilization percentage for write capacity auto-scaling"
  default     = 70
  
  validation {
    condition     = var.autoscaling_write_target_utilization >= 20 && var.autoscaling_write_target_utilization <= 90
    error_message = "Target utilization must be between 20 and 90 percent."
  }
}

# Monitoring and alerting
variable "read_throttle_threshold" {
  type        = number
  description = "Threshold for read throttle alarms"
  default     = 5
  
  validation {
    condition     = var.read_throttle_threshold >= 0
    error_message = "Read throttle threshold must be non-negative."
  }
}

variable "write_throttle_threshold" {
  type        = number
  description = "Threshold for write throttle alarms"
  default     = 5
  
  validation {
    condition     = var.write_throttle_threshold >= 0
    error_message = "Write throttle threshold must be non-negative."
  }
}

variable "alarm_actions" {
  type        = list(string)
  description = "List of actions to execute when CloudWatch alarms are triggered"
  default     = []
  
  validation {
    condition = alltrue([
      for arn in var.alarm_actions :
      can(regex("^arn:aws:sns:", arn))
    ])
    error_message = "Alarm actions must be valid SNS topic ARNs."
  }
}

# Lock cleanup configuration
variable "enable_lock_cleanup" {
  type        = bool
  description = "Enable automatic cleanup of stale locks"
  default     = true
}

variable "max_lock_age_hours" {
  type        = number
  description = "Maximum age of locks in hours before cleanup"
  default     = 24
  
  validation {
    condition     = var.max_lock_age_hours >= 1 && var.max_lock_age_hours <= 168
    error_message = "Max lock age must be between 1 and 168 hours (1 week)."
  }
}

variable "lock_cleanup_schedule" {
  type        = string
  description = "CloudWatch Events schedule expression for lock cleanup"
  default     = "6 hours"
  
  validation {
    condition = can(regex("^(rate\\(.*\\)|cron\\(.*\\))$", "rate(${var.lock_cleanup_schedule})"))
    error_message = "Lock cleanup schedule must be a valid rate expression (e.g., '6 hours', '1 day')."
  }
}

variable "lock_cleanup_dry_run" {
  type        = bool
  description = "Run lock cleanup in dry-run mode (log only, don't delete)"
  default     = false
}

variable "lock_cleanup_sns_topic_arn" {
  type        = string
  description = "SNS topic ARN for lock cleanup notifications"
  default     = ""
  
  validation {
    condition     = var.lock_cleanup_sns_topic_arn == "" || can(regex("^arn:aws:sns:", var.lock_cleanup_sns_topic_arn))
    error_message = "SNS topic ARN must be a valid AWS SNS topic ARN."
  }
}

# Cost optimization
variable "enable_cost_optimization" {
  type        = bool
  description = "Enable cost optimization features"
  default     = true
}

variable "s3_storage_class" {
  type        = string
  description = "Default storage class for S3 objects"
  default     = "STANDARD"
  
  validation {
    condition = contains([
      "STANDARD", "REDUCED_REDUNDANCY", "STANDARD_IA", "ONEZONE_IA",
      "INTELLIGENT_TIERING", "GLACIER", "DEEP_ARCHIVE"
    ], var.s3_storage_class)
    error_message = "Storage class must be a valid S3 storage class."
  }
}

variable "s3_lifecycle_enabled" {
  type        = bool
  description = "Enable S3 lifecycle policies for cost optimization"
  default     = true
}

variable "s3_ia_transition_days" {
  type        = number
  description = "Days before transitioning to Infrequent Access"
  default     = 30
  
  validation {
    condition     = var.s3_ia_transition_days >= 30
    error_message = "IA transition must be at least 30 days."
  }
}

variable "s3_glacier_transition_days" {
  type        = number
  description = "Days before transitioning to Glacier"
  default     = 90
  
  validation {
    condition     = var.s3_glacier_transition_days >= 90
    error_message = "Glacier transition must be at least 90 days."
  }
}

# Compliance and governance
variable "enable_compliance_mode" {
  type        = bool
  description = "Enable compliance mode with additional security controls"
  default     = false
}

variable "compliance_frameworks" {
  type        = list(string)
  description = "List of compliance frameworks to adhere to"
  default     = []
  
  validation {
    condition = alltrue([
      for framework in var.compliance_frameworks :
      contains(["SOC2", "ISO27001", "GDPR", "HIPAA", "PCI-DSS", "NIST"], framework)
    ])
    error_message = "Compliance frameworks must be from: SOC2, ISO27001, GDPR, HIPAA, PCI-DSS, NIST."
  }
}

variable "enable_access_logging" {
  type        = bool
  description = "Enable access logging for all backend resources"
  default     = true
}

variable "log_retention_days" {
  type        = number
  description = "Number of days to retain CloudWatch logs"
  default     = 90
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention must be a valid CloudWatch log retention value."
  }
}

# Backup and disaster recovery
variable "enable_cross_region_backup" {
  type        = bool
  description = "Enable cross-region backup for disaster recovery"
  default     = false
}

variable "backup_region" {
  type        = string
  description = "Secondary region for backup replication"
  default     = ""
  
  validation {
    condition     = var.backup_region == "" || can(regex("^[a-z]{2}(-[a-z]+)+-\\d+$", var.backup_region))
    error_message = "Backup region must be a valid AWS region format."
  }
}

variable "backup_retention_days" {
  type        = number
  description = "Number of days to retain backups"
  default     = 30
  
  validation {
    condition     = var.backup_retention_days >= 7 && var.backup_retention_days <= 365
    error_message = "Backup retention must be between 7 and 365 days."
  }
}

# Common tags
variable "tags" {
  type        = map(string)
  description = "Common tags to apply to all resources"
  default     = {}
  
  validation {
    condition = alltrue([
      for k, v in var.tags :
      length(k) <= 128 && length(v) <= 256
    ])
    error_message = "Tag keys must be <= 128 characters and values <= 256 characters."
  }
}