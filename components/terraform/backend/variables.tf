# Core backend configuration variables
variable "tenant" {
  type        = string
  description = "Tenant name for resource naming"
  default     = "" # Will be set by Atmos
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

variable "region" {
  type        = string
  description = "AWS region"
  default     = "" # Will be set by Atmos

  validation {
    condition     = var.region == "" || can(regex("^[a-z]{2}(-[a-z]+)+-\\d+$", var.region))
    error_message = "Must be a valid AWS region format."
  }
}

variable "iam_role_name" {
  type        = string
  description = "Name of the IAM role to assume for Terraform execution"
  default     = "" # Will be set by Atmos
}

# Security and operational features

variable "enable_access_logging" {
  type        = bool
  description = "Create the access logs bucket and enable S3 server access logging for the state buckets"
  default     = true
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