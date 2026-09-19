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
  description = "Name of the S3 bucket for Terraform state (the -logs and -access-logs buckets derive from it)"

  validation {
    # 63-character S3 limit minus the 12-character "-access-logs" suffix
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,49}[a-z0-9]$", var.bucket_name))
    error_message = "bucket_name must be a DNS-compliant S3 bucket name of 3-51 characters."
  }
}

variable "dynamodb_table_name" {
  type        = string
  description = "DEPRECATED: ignored. State locking uses S3-native lockfiles (use_lockfile); no DynamoDB table is created"
  default     = ""
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

# Security and operational features

variable "enable_deletion_protection" {
  type        = bool
  description = "DEPRECATED: ignored. Protected the removed DynamoDB lock table; state buckets always use prevent_destroy"
  default     = true
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
  description = "Create the access logs bucket and enable S3 server access logging for the state buckets"
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