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

variable "expiration_days" {
  type        = number
  default     = 90
  description = "Number of days after which to expunge the objects"
}

variable "versioning_enabled" {
  type        = bool
  description = "A state of versioning. Versioning is a means of keeping multiple variants of an object in the same bucket"
  default     = true
}

variable "sse_algorithm" {
  type        = string
  description = "The server-side encryption algorithm to use. Valid values are AES256, aws:kms, or aws:kms:dsse"
  default     = "AES256"

  validation {
    condition     = contains(["AES256", "aws:kms", "aws:kms:dsse"], var.sse_algorithm)
    error_message = "sse_algorithm must be one of 'AES256', 'aws:kms', or 'aws:kms:dsse'."
  }
}

variable "force_destroy" {
  type        = bool
  description = "(Optional, Default:false ) A boolean that indicates all objects should be deleted from the bucket so that the bucket can be destroyed without error. These objects are not recoverable"
  default     = false
}

variable "create_access_log_bucket" {
  type        = bool
  default     = false
  description = "Whether or not to create an access log bucket."
}

variable "access_log_bucket_name" {
  type        = string
  default     = ""
  description = "If var.create_access_log_bucket is false, this is the name of the S3 bucket where s3 access logs will be sent to."
}

variable "acl" {
  type        = string
  description = <<-EOT
    The canned ACL to apply. We recommend log-delivery-write for
    compatibility with AWS services. Valid values are private, public-read,
    public-read-write, aws-exec-read, authenticated-read, bucket-owner-read,
    bucket-owner-full-control, log-delivery-write.

    Due to https://docs.aws.amazon.com/AmazonS3/latest/userguide/create-bucket-faq.html, this
    will need to be set to 'private' during creation, but you can update normally after.
    EOT
  default     = "log-delivery-write"
}

variable "policy" {
  type        = string
  default     = ""
  description = <<-EOT
    A valid bucket policy JSON document. This policy will be merged with the
    default CloudTrail bucket policies (AWSCloudTrailAclCheck and AWSCloudTrailWrite).
    EOT
}

variable "object_lock_enabled" {
  type        = bool
  default     = false
  description = "Set to `true` to enable S3 Object Lock on the CloudTrail bucket without configuring a default retention rule, so objects are only protected when a retention period or legal hold is applied per object. Object Lock is also enabled implicitly when `object_lock_configuration` is set. Requires `versioning_enabled = true`."
}

variable "object_lock_configuration" {
  type = object({
    mode  = string           # Valid values are GOVERNANCE and COMPLIANCE.
    days  = optional(number) # Retention period in days. Specify either days or years, not both.
    years = optional(number) # Retention period in years. Specify either days or years, not both.
  })
  default     = null
  description = "A configuration for S3 object locking. With S3 Object Lock, you can store objects using a write-once-read-many (WORM) model. Object lock can help prevent objects from being deleted or overwritten for a fixed amount of time or indefinitely."

  validation {
    condition     = var.object_lock_configuration == null ? true : contains(["GOVERNANCE", "COMPLIANCE"], var.object_lock_configuration.mode)
    error_message = "object_lock_configuration.mode must be either 'GOVERNANCE' or 'COMPLIANCE'."
  }

  validation {
    condition = var.object_lock_configuration == null ? true : (
      (var.object_lock_configuration.days != null && var.object_lock_configuration.years == null) ||
      (var.object_lock_configuration.days == null && var.object_lock_configuration.years != null)
    )
    error_message = "object_lock_configuration requires exactly one of 'days' or 'years' to be set, not both and not neither."
  }
}

check "object_lock_requires_versioning" {
  assert {
    condition     = (var.object_lock_configuration == null && var.object_lock_enabled == false) || var.versioning_enabled == true
    error_message = "S3 Object Lock requires versioning_enabled = true. When object_lock_configuration is set or object_lock_enabled is true, versioning_enabled must be true."
  }
}
