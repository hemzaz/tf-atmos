variable "region" {
  type        = string
  description = "AWS region (the trail's home region)"

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

variable "name" {
  type        = string
  description = "Trail name suffix; resources are named <Environment>-<name>"
  default     = "cloudtrail"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,40}$", var.name))
    error_message = "name must be 1-41 lowercase letters, digits or hyphens, starting with a letter or digit."
  }
}

variable "kms_key_arn" {
  type        = string
  description = "KMS key ARN (kms/main's key_arn) encrypting the trail's log files, its S3 bucket and its CloudWatch log group. The key policy must allow CloudTrail (kms allow_cloudtrail) and CloudWatch Logs (allow_cloudwatch_logs)"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/[a-zA-Z0-9-]+$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN (arn:aws:kms:<region>:<account>:key/<id>)."
  }
}

##############################################
# Trail (Cloud Posse aws-cloudtrail defaults)
##############################################

variable "enable_logging" {
  type        = bool
  description = "Start logging on the trail. False creates the trail stopped"
  default     = true
}

variable "enable_log_file_validation" {
  type        = bool
  description = "Write digest files so log file integrity can be validated (CIS AWS Foundations 3.2)"
  default     = true
}

variable "is_multi_region_trail" {
  type        = bool
  description = "Record management events from every region into this trail (CIS AWS Foundations 3.1)"
  default     = true
}

variable "include_global_service_events" {
  type        = bool
  description = "Record events from global services such as IAM and STS (needed by the IAM and root-usage metric filters)"
  default     = true
}

variable "cloudwatch_logs_retention_in_days" {
  type        = number
  description = "Retention of the trail's CloudWatch log group, which security-monitoring's CIS metric filters read"
  default     = 365

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.cloudwatch_logs_retention_in_days)
    error_message = "cloudwatch_logs_retention_in_days must be a retention period CloudWatch Logs supports (1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288 or 3653)."
  }
}

##############################################
# Log bucket (Cloud Posse aws-cloudtrail-bucket)
##############################################

variable "bucket_glacier_transition_days" {
  type        = number
  description = "Days before log files move to Glacier Flexible Retrieval"
  default     = 90

  validation {
    condition     = var.bucket_glacier_transition_days >= 30
    error_message = "bucket_glacier_transition_days must be at least 30."
  }
}

variable "bucket_expiration_days" {
  type        = number
  description = "Days before log files expire (noncurrent versions follow 30 days later)"
  default     = 365

  validation {
    condition     = var.bucket_expiration_days >= 90
    error_message = "bucket_expiration_days must be at least 90 (CIS keeps a year of trail logs)."
  }
}

variable "force_destroy" {
  type        = bool
  description = "Let terraform destroy the log bucket even when it holds log files"
  default     = false
}
