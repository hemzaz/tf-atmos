variable "domain_name" {
  type        = string
  description = "OpenSearch domain name"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]+$", var.domain_name))
    error_message = "Domain name must start with lowercase letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "engine_version" {
  type        = string
  description = "OpenSearch engine version"
  default     = "OpenSearch_2.11"

  validation {
    condition     = can(regex("^(OpenSearch|Elasticsearch)_[0-9.]+$", var.engine_version))
    error_message = "Invalid engine version format."
  }
}

variable "instance_type" {
  type        = string
  description = "Instance type for data nodes"
  default     = "t3.small.search"
}

variable "instance_count" {
  type        = number
  description = "Number of data nodes"
  default     = 2

  validation {
    condition     = var.instance_count >= 1
    error_message = "Instance count must be at least 1."
  }
}

variable "dedicated_master_enabled" {
  type        = bool
  description = "Enable dedicated master nodes"
  default     = false
}

variable "dedicated_master_type" {
  type        = string
  description = "Instance type for dedicated master nodes"
  default     = "t3.small.search"
}

variable "dedicated_master_count" {
  type        = number
  description = "Number of dedicated master nodes"
  default     = 3

  validation {
    condition     = var.dedicated_master_count == 0 || var.dedicated_master_count == 3 || var.dedicated_master_count == 5
    error_message = "Dedicated master count must be 0, 3, or 5."
  }
}

variable "zone_awareness_enabled" {
  type        = bool
  description = "Enable multi-AZ deployment"
  default     = true
}

variable "availability_zone_count" {
  type        = number
  description = "Number of availability zones (2 or 3)"
  default     = 2

  validation {
    condition     = var.availability_zone_count == 2 || var.availability_zone_count == 3
    error_message = "Availability zone count must be 2 or 3."
  }
}

variable "warm_enabled" {
  type        = bool
  description = "Enable warm storage"
  default     = false
}

variable "warm_count" {
  type        = number
  description = "Number of warm nodes"
  default     = 2
}

variable "warm_type" {
  type        = string
  description = "Instance type for warm nodes"
  default     = "ultrawarm1.medium.search"
}

variable "cold_storage_enabled" {
  type        = bool
  description = "Enable cold storage"
  default     = false
}

variable "ebs_volume_size" {
  type        = number
  description = "EBS volume size in GB"
  default     = 100

  validation {
    condition     = var.ebs_volume_size >= 10 && var.ebs_volume_size <= 16384
    error_message = "EBS volume size must be between 10 and 16384 GB."
  }
}

variable "ebs_volume_type" {
  type        = string
  description = "EBS volume type (gp2, gp3, io1, standard)"
  default     = "gp3"

  validation {
    condition     = contains(["gp2", "gp3", "io1", "standard"], var.ebs_volume_type)
    error_message = "Invalid EBS volume type."
  }
}

variable "ebs_iops" {
  type        = number
  description = "EBS IOPS (for gp3 or io1)"
  default     = 3000

  validation {
    condition     = var.ebs_iops >= 3000 && var.ebs_iops <= 16000
    error_message = "EBS IOPS must be between 3000 and 16000."
  }
}

variable "ebs_throughput" {
  type        = number
  description = "EBS throughput in MiB/s (for gp3)"
  default     = 125

  validation {
    condition     = var.ebs_throughput >= 125 && var.ebs_throughput <= 1000
    error_message = "EBS throughput must be between 125 and 1000 MiB/s."
  }
}

variable "kms_key_id" {
  type        = string
  description = "KMS key ID for encryption"
  default     = null
}

variable "tls_security_policy" {
  type        = string
  description = "TLS security policy"
  default     = "Policy-Min-TLS-1-2-2019-07"

  validation {
    condition     = can(regex("^Policy-Min-TLS-1-[02]-", var.tls_security_policy))
    error_message = "Invalid TLS security policy."
  }
}

variable "custom_endpoint" {
  type        = string
  description = "Custom endpoint domain name"
  default     = null
}

variable "custom_endpoint_certificate_arn" {
  type        = string
  description = "ACM certificate ARN for custom endpoint"
  default     = null
}

variable "vpc_id" {
  type        = string
  description = "VPC ID for VPC deployment"
  default     = null
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs for VPC deployment"
  default     = null
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  description = "CIDR blocks allowed to access OpenSearch"
  default     = []
}

variable "internal_user_database_enabled" {
  type        = bool
  description = "Enable internal user database"
  default     = false
}

variable "master_user_arn" {
  type        = string
  description = "IAM ARN for master user"
  default     = null
}

variable "master_user_name" {
  type        = string
  description = "Master username (for internal database)"
  default     = null
  sensitive   = true
}

variable "master_user_password" {
  type        = string
  description = "Master password (for internal database)"
  default     = null
  sensitive   = true
}

variable "cognito_user_pool_id" {
  type        = string
  description = "Cognito user pool ID"
  default     = null
}

variable "cognito_identity_pool_id" {
  type        = string
  description = "Cognito identity pool ID"
  default     = null
}

variable "access_principals" {
  type        = list(string)
  description = "IAM principal ARNs with access to domain"
  default     = ["*"]
}

variable "advanced_options" {
  type        = map(string)
  description = "Advanced options"
  default     = {}
}

variable "auto_tune_enabled" {
  type        = bool
  description = "Enable Auto-Tune"
  default     = true
}

variable "auto_tune_rollback_on_disable" {
  type        = string
  description = "Auto-Tune rollback on disable"
  default     = "NO_ROLLBACK"

  validation {
    condition     = contains(["NO_ROLLBACK", "DEFAULT_ROLLBACK"], var.auto_tune_rollback_on_disable)
    error_message = "Rollback must be NO_ROLLBACK or DEFAULT_ROLLBACK."
  }
}

variable "auto_tune_start_at" {
  type        = string
  description = "Auto-Tune maintenance start time (RFC3339)"
  default     = null
}

variable "auto_tune_duration_value" {
  type        = number
  description = "Auto-Tune maintenance window duration value"
  default     = 2
}

variable "auto_tune_duration_unit" {
  type        = string
  description = "Auto-Tune maintenance window duration unit"
  default     = "HOURS"

  validation {
    condition     = contains(["HOURS"], var.auto_tune_duration_unit)
    error_message = "Duration unit must be HOURS."
  }
}

variable "auto_tune_cron_expression" {
  type        = string
  description = "Auto-Tune cron expression for recurrence"
  default     = "cron(0 3 ? * SUN *)"
}

variable "automated_snapshot_start_hour" {
  type        = number
  description = "Automated snapshot start hour (0-23 UTC)"
  default     = 3

  validation {
    condition     = var.automated_snapshot_start_hour >= 0 && var.automated_snapshot_start_hour <= 23
    error_message = "Snapshot start hour must be between 0 and 23."
  }
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

variable "free_storage_threshold_mb" {
  type        = number
  description = "Free storage alarm threshold in MB"
  default     = 10240

  validation {
    condition     = var.free_storage_threshold_mb > 0
    error_message = "Free storage threshold must be positive."
  }
}

variable "cpu_utilization_threshold" {
  type        = number
  description = "CPU utilization alarm threshold percentage"
  default     = 80

  validation {
    condition     = var.cpu_utilization_threshold > 0 && var.cpu_utilization_threshold <= 100
    error_message = "CPU threshold must be between 0 and 100."
  }
}

variable "jvm_memory_pressure_threshold" {
  type        = number
  description = "JVM memory pressure alarm threshold percentage"
  default     = 85

  validation {
    condition     = var.jvm_memory_pressure_threshold > 0 && var.jvm_memory_pressure_threshold <= 100
    error_message = "JVM memory threshold must be between 0 and 100."
  }
}

variable "alarm_actions" {
  type        = list(string)
  description = "List of ARNs for alarm actions (SNS topics)"
  default     = []
}

variable "create_service_linked_role" {
  type        = bool
  description = "Create OpenSearch service-linked role"
  default     = false
}

variable "tags" {
  type        = map(string)
  description = "Additional tags for all resources"
  default     = {}
}
