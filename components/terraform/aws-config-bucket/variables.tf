variable "region" {
  type        = string
  description = "AWS Region"
}

variable "lifecycle_rule_enabled" {
  type        = bool
  description = "Enable lifecycle events on this bucket"
  default     = true
}

variable "noncurrent_version_expiration_days" {
  type        = number
  default     = 90
  description = "Specifies when noncurrent object versions expire"
}

variable "noncurrent_version_transition_days" {
  type        = number
  default     = 30
  description = "Specifies when noncurrent object versions transition to a different storage tier"
}

variable "standard_transition_days" {
  type        = number
  default     = 30
  description = "Number of days to persist in the standard storage tier before moving to the infrequent access tier"
}

variable "glacier_transition_days" {
  type        = number
  default     = 60
  description = "Number of days after which to move the data to the glacier storage tier"
}

variable "enable_glacier_transition" {
  type        = bool
  default     = true
  description = "Enables the transition to AWS Glacier (note that this can incur unnecessary costs for huge amount of small files"
}

variable "expiration_days" {
  type        = number
  default     = 90
  description = "Number of days after which to expunge the objects"
}

variable "access_log_bucket_name" {
  type        = string
  default     = ""
  description = "Name of the S3 bucket where s3 access log will be sent to"
}

variable "kms_master_key_arn" {
  type        = string
  description = <<-EOT
    ARN of the customer managed KMS key that encrypts the bucket (SSE-KMS). Required, no default:
    a key ARN (arn:<partition>:kms:<region>:<account>:key/<id>), never an alias ARN or the
    AWS managed aws/s3 key. Its key policy must let config.amazonaws.com use it for the delivering
    accounts. House input (owner 2026-11-04); upstream has none and uses SSE-S3.
    EOT
  nullable    = false

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:kms:[a-z]{2}(-[a-z]+)+-[0-9]:[0-9]{12}:key/[0-9a-zA-Z-]+$", var.kms_master_key_arn))
    error_message = "kms_master_key_arn must be a customer managed KMS key ARN (arn:aws:kms:<region>:<12-digit account>:key/<key id>), not an alias ARN or the AWS managed aws/s3 key."
  }
}
