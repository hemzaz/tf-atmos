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

variable "bucket_name" {
  description = "Name of the S3 bucket (must be globally unique)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.bucket_name))
    error_message = "Bucket name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "enable_versioning" {
  description = "Enable versioning for the bucket"
  type        = bool
  default     = true
}

variable "enable_mfa_delete" {
  description = "Enable MFA delete (requires versioning to be enabled)"
  type        = bool
  default     = false
}

variable "enable_encryption" {
  description = "Enable server-side encryption"
  type        = bool
  default     = true
}

variable "encryption_type" {
  description = "Type of server-side encryption (sse-s3, sse-kms, dsse-kms)"
  type        = string
  default     = "sse-s3"

  validation {
    condition     = contains(["sse-s3", "sse-kms", "dsse-kms"], var.encryption_type)
    error_message = "Encryption type must be sse-s3, sse-kms, or dsse-kms."
  }
}

variable "kms_key_id" {
  description = "KMS key ID for SSE-KMS or DSSE-KMS encryption (required if encryption_type is sse-kms or dsse-kms)"
  type        = string
  default     = null
}

variable "block_public_access" {
  description = "Block all public access to the bucket"
  type        = bool
  default     = true
}

variable "enable_public_read" {
  description = "Enable public read access (requires block_public_access to be false)"
  type        = bool
  default     = false
}

variable "lifecycle_rules" {
  description = "List of lifecycle rules for the bucket"
  type = list(object({
    id      = string
    enabled = bool
    prefix  = optional(string)
    tags    = optional(map(string))

    expiration = optional(object({
      days                         = optional(number)
      expired_object_delete_marker = optional(bool)
    }))

    transitions = optional(list(object({
      days          = number
      storage_class = string
    })))

    noncurrent_version_transitions = optional(list(object({
      noncurrent_days = number
      storage_class   = string
    })))

    noncurrent_version_expiration = optional(object({
      noncurrent_days = number
    }))

    abort_incomplete_multipart_upload_days = optional(number)
  }))
  default = []
}

variable "enable_website" {
  description = "Enable static website hosting"
  type        = bool
  default     = false
}

variable "website_index_document" {
  description = "Index document for website"
  type        = string
  default     = "index.html"
}

variable "website_error_document" {
  description = "Error document for website"
  type        = string
  default     = "error.html"
}

variable "cors_rules" {
  description = "List of CORS rules"
  type = list(object({
    allowed_headers = list(string)
    allowed_methods = list(string)
    allowed_origins = list(string)
    expose_headers  = optional(list(string))
    max_age_seconds = optional(number)
  }))
  default = []
}

variable "enable_logging" {
  description = "Enable S3 access logging"
  type        = bool
  default     = false
}

variable "logging_target_bucket" {
  description = "Target bucket for access logs (required if enable_logging is true)"
  type        = string
  default     = null
}

variable "logging_target_prefix" {
  description = "Prefix for access logs"
  type        = string
  default     = "logs/"
}

variable "enable_replication" {
  description = "Enable cross-region or same-region replication"
  type        = bool
  default     = false
}

variable "replication_role_arn" {
  description = "IAM role ARN for replication (required if enable_replication is true)"
  type        = string
  default     = null
}

variable "replication_rules" {
  description = "List of replication rules"
  type = list(object({
    id                        = string
    priority                  = number
    destination_bucket_arn    = string
    destination_storage_class = optional(string)
    replica_kms_key_id        = optional(string)
    prefix                    = optional(string)
    filter_tags               = optional(map(string))
  }))
  default = []
}

variable "enable_object_lock" {
  description = "Enable object lock (can only be enabled at bucket creation)"
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

variable "enable_intelligent_tiering" {
  description = "Enable Intelligent-Tiering configuration"
  type        = bool
  default     = false
}

variable "intelligent_tiering_archive_days" {
  description = "Days before archiving to Archive Access tier"
  type        = number
  default     = 90
}

variable "intelligent_tiering_deep_archive_days" {
  description = "Days before archiving to Deep Archive Access tier"
  type        = number
  default     = 180
}

variable "event_notifications" {
  description = "List of event notifications"
  type = list(object({
    id          = string
    events      = list(string)
    destination_type = string  # sns, sqs, or lambda
    destination_arn  = string
    filter_prefix    = optional(string)
    filter_suffix    = optional(string)
  }))
  default = []
}

variable "bucket_policy" {
  description = "Custom bucket policy (JSON string)"
  type        = string
  default     = null
}

variable "enable_inventory" {
  description = "Enable S3 inventory"
  type        = bool
  default     = false
}

variable "inventory_destination_bucket" {
  description = "Destination bucket for inventory reports"
  type        = string
  default     = null
}

variable "enable_request_metrics" {
  description = "Enable request metrics"
  type        = bool
  default     = false
}

variable "force_destroy" {
  description = "Allow bucket to be destroyed even if it contains objects"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
