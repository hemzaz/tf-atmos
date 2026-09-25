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
  description = "Short name. The workgroup and each named query are named <Environment>-<name>[-<named_queries key>]"

  validation {
    condition     = can(regex("^[a-z0-9-]{1,40}$", var.name))
    error_message = "name must be 1-40 characters of lowercase letters, digits or hyphens."
  }
}

variable "description" {
  type        = string
  description = "Workgroup description"
  default     = ""
}

variable "output_location" {
  type        = string
  description = "s3:// URI query results are written to, e.g. the output of a data-pipeline/s3-athena-results instance (s3://<bucket>/)"

  validation {
    condition     = can(regex("^s3://[a-z0-9][a-z0-9.-]{1,61}[a-z0-9](/.*)?$", var.output_location))
    error_message = "output_location must be an s3:// URI (s3://<bucket>[/<prefix>/])."
  }
}

variable "kms_key_arn" {
  type        = string
  description = "Customer managed KMS key ARN the workgroup's SSE_KMS result encryption uses"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/.+$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN (arn:aws:kms:<region>:<account>:key/<id>)."
  }
}

variable "enforce_workgroup_configuration" {
  type        = bool
  description = "Force every query in the workgroup to use this workgroup's own settings (output location, encryption, bytes scanned cutoff) instead of client-supplied ones"
  default     = true
}

variable "publish_cloudwatch_metrics_enabled" {
  type        = bool
  description = "Publish workgroup query metrics to CloudWatch"
  default     = true
}

variable "bytes_scanned_cutoff_per_query" {
  type        = number
  description = "Cancel a query once it scans this many bytes. null disables the cutoff. Must be at least 10485760 (10 MB, the AWS minimum) when set"
  default     = null

  validation {
    condition     = var.bytes_scanned_cutoff_per_query == null || var.bytes_scanned_cutoff_per_query >= 10485760
    error_message = "bytes_scanned_cutoff_per_query must be null or at least 10485760 (10 MB)."
  }
}

variable "engine_version" {
  type        = string
  description = "Athena engine version selector, e.g. \"Athena engine version 3\" or \"AUTO\""
  default     = "Athena engine version 3"
}

variable "requester_pays_enabled" {
  type        = bool
  description = "Allow queries against requester-pays S3 buckets"
  default     = false
}

variable "force_destroy" {
  type        = bool
  description = "Let terraform delete the workgroup even when it has saved queries; without this, a non-empty workgroup blocks destroy"
  default     = false
}

variable "named_queries" {
  type = map(object({
    database    = string
    query       = string
    description = optional(string, "")
  }))
  description = "Saved queries, keyed by a short suffix (each is named <Environment>-<name>-<key>). database is the Glue/Athena database name to run against, e.g. from a glue component instance's database_name output"
  default     = {}
  nullable    = false
}
