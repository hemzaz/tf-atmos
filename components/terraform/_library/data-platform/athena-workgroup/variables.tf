variable "workgroup_name" {
  type        = string
  description = "Athena workgroup name"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]+$", var.workgroup_name))
    error_message = "Workgroup name must contain only letters, numbers, periods, underscores, and hyphens."
  }
}

variable "description" {
  type        = string
  description = "Workgroup description"
  default     = "Managed by Terraform"
}

variable "state" {
  type        = string
  description = "Workgroup state (ENABLED or DISABLED)"
  default     = "ENABLED"

  validation {
    condition     = contains(["ENABLED", "DISABLED"], var.state)
    error_message = "State must be ENABLED or DISABLED."
  }
}

variable "output_location" {
  type        = string
  description = "S3 output location for query results"

  validation {
    condition     = can(regex("^s3://", var.output_location))
    error_message = "Output location must be an S3 URI."
  }
}

variable "output_bucket_arn" {
  type        = string
  description = "S3 output bucket ARN (for IAM policy)"
  default     = ""
}

variable "source_bucket_arns" {
  type        = list(string)
  description = "List of source S3 bucket ARNs for queries"
  default     = []
}

variable "encryption_option" {
  type        = string
  description = "Encryption option (SSE_S3, SSE_KMS, CSE_KMS)"
  default     = "SSE_S3"

  validation {
    condition     = var.encryption_option == null || contains(["SSE_S3", "SSE_KMS", "CSE_KMS"], var.encryption_option)
    error_message = "Encryption option must be SSE_S3, SSE_KMS, or CSE_KMS."
  }
}

variable "kms_key_arn" {
  type        = string
  description = "KMS key ARN for encryption (required for SSE_KMS or CSE_KMS)"
  default     = null
}

variable "s3_acl_option" {
  type        = string
  description = "S3 ACL option for query results"
  default     = null

  validation {
    condition     = var.s3_acl_option == null || contains(["BUCKET_OWNER_FULL_CONTROL"], var.s3_acl_option)
    error_message = "S3 ACL option must be BUCKET_OWNER_FULL_CONTROL."
  }
}

variable "expected_bucket_owner" {
  type        = string
  description = "Expected bucket owner AWS account ID"
  default     = null
}

variable "bytes_scanned_cutoff" {
  type        = number
  description = "Per-query data scanned cutoff in bytes (null for no limit)"
  default     = null

  validation {
    condition     = var.bytes_scanned_cutoff == null || var.bytes_scanned_cutoff > 0
    error_message = "Bytes scanned cutoff must be positive."
  }
}

variable "enforce_workgroup_config" {
  type        = bool
  description = "Enforce workgroup configuration for queries"
  default     = true
}

variable "enable_cloudwatch_metrics" {
  type        = bool
  description = "Publish CloudWatch metrics"
  default     = true
}

variable "engine_version" {
  type        = string
  description = "Athena engine version (AUTO, Athena engine version 2, or 3)"
  default     = "AUTO"

  validation {
    condition     = var.engine_version == null || can(regex("^(AUTO|Athena engine version [23])$", var.engine_version))
    error_message = "Engine version must be AUTO, 'Athena engine version 2', or 'Athena engine version 3'."
  }
}

variable "requester_pays_enabled" {
  type        = bool
  description = "Enable requester pays for S3 buckets"
  default     = false
}

variable "force_destroy" {
  type        = bool
  description = "Force destroy workgroup even with queries"
  default     = false
}

variable "named_queries" {
  type = map(object({
    database    = string
    query       = string
    description = optional(string)
  }))
  description = "Map of named queries"
  default     = {}
}

variable "data_catalogs" {
  type = map(object({
    type        = string
    description = optional(string)
    parameters  = optional(map(string), {})
  }))
  description = "Map of data catalogs"
  default     = {}

  validation {
    condition = alltrue([
      for k, v in var.data_catalogs :
      contains(["LAMBDA", "GLUE", "HIVE"], v.type)
    ])
    error_message = "Data catalog type must be LAMBDA, GLUE, or HIVE."
  }
}

variable "prepared_statements" {
  type = map(object({
    query       = string
    description = optional(string)
  }))
  description = "Map of prepared statements"
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

variable "query_execution_threshold_ms" {
  type        = number
  description = "Query execution time alarm threshold in milliseconds"
  default     = 60000

  validation {
    condition     = var.query_execution_threshold_ms > 0
    error_message = "Query execution threshold must be positive."
  }
}

variable "data_scanned_threshold_bytes" {
  type        = number
  description = "Data scanned alarm threshold in bytes"
  default     = 107374182400

  validation {
    condition     = var.data_scanned_threshold_bytes > 0
    error_message = "Data scanned threshold must be positive."
  }
}

variable "query_planning_threshold_ms" {
  type        = number
  description = "Query planning time alarm threshold in milliseconds"
  default     = 10000

  validation {
    condition     = var.query_planning_threshold_ms > 0
    error_message = "Query planning threshold must be positive."
  }
}

variable "enable_cost_control" {
  type        = bool
  description = "Enable cost control alarms"
  default     = true
}

variable "daily_cost_threshold_bytes" {
  type        = number
  description = "Daily data scanned cost threshold in bytes"
  default     = 1099511627776

  validation {
    condition     = var.daily_cost_threshold_bytes > 0
    error_message = "Daily cost threshold must be positive."
  }
}

variable "alarm_actions" {
  type        = list(string)
  description = "List of ARNs for alarm actions (SNS topics)"
  default     = []
}

variable "create_iam_policy" {
  type        = bool
  description = "Create IAM policy for workgroup access"
  default     = true
}

variable "tags" {
  type        = map(string)
  description = "Additional tags for all resources"
  default     = {}
}
