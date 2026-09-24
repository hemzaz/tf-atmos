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

variable "name" {
  type        = string
  description = "Name suffix; resources are named <Environment>-<name>"
  default     = "awsconfig"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,40}$", var.name))
    error_message = "name must be 1-41 lowercase letters, digits or hyphens, starting with a letter or digit."
  }
}

variable "kms_key_arn" {
  type        = string
  description = "KMS key ARN (kms/main's key_arn) encrypting the configuration snapshots and history in the S3 bucket"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/[a-zA-Z0-9-]+$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN (arn:aws:kms:<region>:<account>:key/<id>)."
  }
}

##############################################
# Recorder (Cloud Posse aws-config defaults)
##############################################

variable "enable_recorder" {
  type        = bool
  description = "Start the configuration recorder. False creates it stopped"
  default     = true
}

variable "include_global_resource_types" {
  type        = bool
  description = "Record global resources (IAM users, roles, policies). Turn on in exactly one region per account (Cloud Posse's global_resource_collector_region); every stack here is its own account in one region"
  default     = true
}

variable "recording_frequency" {
  type        = string
  description = "CONTINUOUS records every change; DAILY records at most one change per resource per day (cheaper, but Security Hub controls re-evaluate a day late)"
  default     = "CONTINUOUS"

  validation {
    condition     = contains(["CONTINUOUS", "DAILY"], var.recording_frequency)
    error_message = "recording_frequency must be CONTINUOUS or DAILY."
  }
}

variable "delivery_frequency" {
  type        = string
  description = "How often configuration snapshots are delivered to the bucket"
  default     = "TwentyFour_Hours"

  validation {
    condition     = contains(["One_Hour", "Three_Hours", "Six_Hours", "Twelve_Hours", "TwentyFour_Hours"], var.delivery_frequency)
    error_message = "delivery_frequency must be One_Hour, Three_Hours, Six_Hours, Twelve_Hours or TwentyFour_Hours."
  }
}

##############################################
# Storage bucket (Cloud Posse aws-config-bucket)
##############################################

variable "bucket_glacier_transition_days" {
  type        = number
  description = "Days before snapshots and history move to Glacier Flexible Retrieval"
  default     = 90

  validation {
    condition     = var.bucket_glacier_transition_days >= 30
    error_message = "bucket_glacier_transition_days must be at least 30."
  }
}

variable "bucket_expiration_days" {
  type        = number
  description = "Days before snapshots and history expire (noncurrent versions follow 30 days later)"
  default     = 365

  validation {
    condition     = var.bucket_expiration_days >= 90
    error_message = "bucket_expiration_days must be at least 90."
  }
}

variable "force_destroy" {
  type        = bool
  description = "Let terraform destroy the bucket even when it holds objects"
  default     = false
}
