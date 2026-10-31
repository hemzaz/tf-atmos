variable "region" {
  type        = string
  description = "AWS Region"
}

variable "account_alias" {
  type        = string
  description = "The IAM account alias. If not set, uses the module ID"
  default     = null
}

variable "account_alias_enabled" {
  type        = bool
  description = "Whether to create the IAM account alias"
  default     = true
}

variable "s3_block_public_access_enabled" {
  type        = bool
  description = "Whether to enable S3 account-level public access block"
  default     = true
}

variable "s3_block_public_acls" {
  type        = bool
  description = "Whether to block public ACLs"
  default     = true
}

variable "s3_block_public_policy" {
  type        = bool
  description = "Whether to block public bucket policies"
  default     = true
}

variable "s3_ignore_public_acls" {
  type        = bool
  description = "Whether to ignore public ACLs"
  default     = true
}

variable "s3_restrict_public_buckets" {
  type        = bool
  description = "Whether to restrict public buckets"
  default     = true
}

variable "ebs_default_encryption_enabled" {
  type        = bool
  description = "Whether to enable EBS default encryption"
  default     = true
}

variable "ebs_default_kms_key_arn" {
  type        = string
  description = "The ARN of the KMS key for EBS default encryption. If not set, uses the AWS-managed key."
  default     = null
}

variable "billing_contact" {
  type = object({
    name          = string
    title         = string
    email_address = string
    phone_number  = string
  })
  description = "Billing alternate contact information"
  default     = null
}

variable "operations_contact" {
  type = object({
    name          = string
    title         = string
    email_address = string
    phone_number  = string
  })
  description = "Operations alternate contact information"
  default     = null
}

variable "security_contact" {
  type = object({
    name          = string
    title         = string
    email_address = string
    phone_number  = string
  })
  description = "Security alternate contact information"
  default     = null
}

variable "ssm_block_public_document_sharing" {
  type        = bool
  description = "Whether to block public document sharing in SSM"
  default     = false
}

variable "ssm_session_preferences_enabled" {
  type        = bool
  description = "Whether to configure SSM Session Manager preferences (idle timeout)"
  default     = false
}

variable "ssm_session_idle_timeout_minutes" {
  type        = number
  description = "The idle session timeout in minutes for SSM Session Manager. AWS default is 20 minutes."
  default     = 20

  validation {
    condition     = var.ssm_session_idle_timeout_minutes >= 1 && var.ssm_session_idle_timeout_minutes <= 60
    error_message = "ssm_session_idle_timeout_minutes must be between 1 and 60 minutes."
  }
}

variable "ebs_snapshot_block_public_access_enabled" {
  type        = bool
  description = "Whether to enable EBS snapshot block public access"
  default     = true
}

variable "ebs_snapshot_block_public_access_state" {
  type        = string
  description = "The state of EBS snapshot block public access. Valid values are 'block-all-sharing', 'block-new-sharing', and 'unblocked'."
  default     = "block-all-sharing"

  validation {
    condition     = contains(["block-all-sharing", "block-new-sharing", "unblocked"], var.ebs_snapshot_block_public_access_state)
    error_message = "ebs_snapshot_block_public_access_state must be either 'block-all-sharing' or 'block-new-sharing' or 'unblocked'."
  }
}

variable "ec2_instance_metadata_defaults_enabled" {
  type        = bool
  description = "Whether to configure EC2 instance metadata defaults"
  default     = true
}

variable "ec2_instance_metadata_http_endpoint" {
  type        = string
  description = "Whether the instance metadata service is available. Valid values are 'enabled', 'disabled', and 'no-preference'."
  default     = "enabled"

  validation {
    condition     = contains(["enabled", "disabled", "no-preference"], var.ec2_instance_metadata_http_endpoint)
    error_message = "ec2_instance_metadata_http_endpoint must be either 'enabled' or 'disabled' or 'no-preference'."
  }
}

variable "ec2_instance_metadata_http_tokens" {
  type        = string
  description = "Whether the instance metadata service requires session tokens (IMDSv2). Valid values are 'required', 'optional', and 'no-preference'."
  default     = "required"

  validation {
    condition     = contains(["required", "optional", "no-preference"], var.ec2_instance_metadata_http_tokens)
    error_message = "ec2_instance_metadata_http_tokens must be either 'required' or 'optional' or 'no-preference'."
  }
}

variable "ec2_instance_metadata_http_put_response_hop_limit" {
  type        = number
  description = "The desired HTTP PUT response hop limit for instance metadata requests. Valid values are between 1 and 64, or -1 for no preference."
  default     = 1

  validation {
    condition     = var.ec2_instance_metadata_http_put_response_hop_limit == -1 || (var.ec2_instance_metadata_http_put_response_hop_limit >= 1 && var.ec2_instance_metadata_http_put_response_hop_limit <= 64)
    error_message = "ec2_instance_metadata_http_put_response_hop_limit must be -1 for no preference, or between 1 and 64."
  }
}

variable "ec2_instance_metadata_tags" {
  type        = string
  description = "Whether to enable access to instance tags from the instance metadata service. Valid values are 'enabled', 'disabled', and 'no-preference'."
  default     = "enabled"

  validation {
    condition     = contains(["enabled", "disabled", "no-preference"], var.ec2_instance_metadata_tags)
    error_message = "ec2_instance_metadata_tags must be either 'enabled' or 'disabled' or 'no-preference'."
  }
}

variable "ec2_image_block_public_access_enabled" {
  type        = bool
  description = "Whether to enable EC2 AMI block public access"
  default     = true
}

variable "ec2_image_block_public_access_state" {
  type        = string
  description = "The state of EC2 AMI block public access. Valid values are 'block-new-sharing' and 'unblocked'."
  default     = "block-new-sharing"

  validation {
    condition     = contains(["block-new-sharing", "unblocked"], var.ec2_image_block_public_access_state)
    error_message = "ec2_image_block_public_access_state must be either 'block-new-sharing' or 'unblocked'."
  }
}

variable "emr_block_public_access_enabled" {
  type        = bool
  description = "Whether to configure EMR block public access"
  default     = true
}

variable "emr_block_public_security_group_rules" {
  type        = bool
  description = "Whether to block EMR clusters from being created with public security group rules"
  default     = true
}

variable "emr_permitted_public_security_group_rule_ranges" {
  type = list(object({
    min_range = number
    max_range = number
  }))
  description = "List of permitted port ranges for public security group rules in EMR. Each object must have min_range and max_range. Default is an empty list (no permitted ranges)."
  default     = []
}
