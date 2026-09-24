variable "region" {
  type        = string
  description = "AWS region"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-\\d+$", var.region))
    error_message = "The region must be a valid AWS region name (e.g., us-east-1, eu-west-1)."
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

variable "enabled" {
  type        = bool
  description = "Set to false to prevent the component from creating any resources"
  default     = true
}

variable "name" {
  type        = string
  description = "Short name. Unless bucket_name is set, the bucket is named <Environment>-<name>-<account id> (S3 bucket names are global)"

  validation {
    condition     = can(regex("^[a-z0-9-]{1,30}$", var.name))
    error_message = "name must be 1-30 characters of lowercase letters, digits or hyphens."
  }
}

variable "kms_key_arn" {
  type        = string
  description = "Customer managed KMS key ARN for the bucket's default encryption (SSE-KMS)"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/.+$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN (arn:aws:kms:<region>:<account>:key/<id>)."
  }
}

# The inputs below are Cloud Posse's aws-s3-bucket inputs. Defaults are Cloud
# Posse's except bucket_key_enabled (true here, to cut KMS request costs).

variable "bucket_name" {
  type        = string
  description = "Full bucket name, overriding <Environment>-<name>-<account id>"
  default     = ""
  nullable    = false

  validation {
    condition     = var.bucket_name == "" || can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "bucket_name must be empty or a valid S3 bucket name (3-63 characters of lowercase letters, digits, dots or hyphens)."
  }
}

variable "bucket_key_enabled" {
  type        = bool
  description = "Use an S3 Bucket Key for SSE-KMS, which cuts KMS requests (and cost) by reusing a bucket-level data key"
  default     = true
}

variable "versioning_enabled" {
  type        = bool
  description = "Keep every version of every object (Suspended when false)"
  default     = true
}

variable "force_destroy" {
  type        = bool
  description = "Let terraform destroy the bucket even when it holds objects. They are deleted and cannot be recovered"
  default     = false
}

variable "logging" {
  type = object({
    bucket_name = string
    prefix      = optional(string, "")
  })
  description = "Server access logging to another bucket: {bucket_name, prefix}. null disables it. The target bucket must use SSE-S3 (S3 cannot deliver access logs to an SSE-KMS bucket, so not one from this component)"
  default     = null

  validation {
    condition     = var.logging == null || can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.logging.bucket_name))
    error_message = "logging.bucket_name must be a valid S3 bucket name."
  }
}

variable "lifecycle_configuration_rules" {
  type = list(object({
    enabled = optional(bool, true)
    id      = string

    abort_incomplete_multipart_upload_days = optional(number)

    # `filter_and` is the only place to set a prefix.
    filter_and = optional(object({
      object_size_greater_than = optional(number)
      object_size_less_than    = optional(number)
      prefix                   = optional(string)
      tags                     = optional(map(string), {})
    }))
    expiration = optional(object({
      date                         = optional(string)
      days                         = optional(number)
      expired_object_delete_marker = optional(bool)
    }))
    noncurrent_version_expiration = optional(object({
      newer_noncurrent_versions = optional(number)
      noncurrent_days           = optional(number)
    }))
    transition = optional(list(object({
      date          = optional(string)
      days          = optional(number)
      storage_class = optional(string)
    })), [])
    noncurrent_version_transition = optional(list(object({
      newer_noncurrent_versions = optional(number)
      noncurrent_days           = optional(number)
      storage_class             = optional(string)
    })), [])
  }))
  description = "Lifecycle rules, as Cloud Posse's lifecycle_configuration_rules (one entry per aws_s3_bucket_lifecycle_configuration rule)"
  default     = []
  nullable    = false

  validation {
    condition     = length(distinct([for r in var.lifecycle_configuration_rules : r.id])) == length(var.lifecycle_configuration_rules)
    error_message = "Each lifecycle rule needs a unique id."
  }

  validation {
    condition = alltrue(flatten([for r in var.lifecycle_configuration_rules : [
      for t in concat(r.transition, r.noncurrent_version_transition) :
      contains(["GLACIER", "STANDARD_IA", "ONEZONE_IA", "INTELLIGENT_TIERING", "DEEP_ARCHIVE", "GLACIER_IR"], coalesce(t.storage_class, "-"))
    ]]))
    error_message = "Transition storage_class must be one of GLACIER, STANDARD_IA, ONEZONE_IA, INTELLIGENT_TIERING, DEEP_ARCHIVE or GLACIER_IR."
  }
}

variable "source_policy_documents" {
  type        = list(string)
  description = "Bucket policy documents (JSON) merged with the TLS-only statement, e.g. to grant a CloudFront distribution read access. Statement IDs must be unique"
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for d in var.source_policy_documents : can(jsondecode(d))])
    error_message = "Each source_policy_documents entry must be a JSON document."
  }
}
