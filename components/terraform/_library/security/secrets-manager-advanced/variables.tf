variable "name_prefix" {
  type        = string
  description = "Prefix for resource names"
}

variable "description" {
  type        = string
  description = "Secret description"
  default     = "Managed by Terraform"
}

variable "secret_string" {
  type        = string
  description = "Secret value (JSON string)"
  default     = null
  sensitive   = true
}

variable "secret_binary" {
  type        = string
  description = "Binary secret value (base64)"
  default     = null
  sensitive   = true
}

variable "kms_key_id" {
  type        = string
  description = "KMS key ID for encryption"
  default     = null
}

variable "enable_rotation" {
  type        = bool
  description = "Enable automatic rotation"
  default     = false
}

variable "rotation_days" {
  type        = number
  description = "Rotation frequency in days"
  default     = 30

  validation {
    condition     = var.rotation_days >= 1 && var.rotation_days <= 365
    error_message = "Rotation days must be between 1 and 365."
  }
}

variable "rotation_lambda_arn" {
  type        = string
  description = "Lambda function ARN for rotation"
  default     = ""
}

variable "recovery_window_days" {
  type        = number
  description = "Recovery window in days (0 for immediate deletion)"
  default     = 30

  validation {
    condition     = var.recovery_window_days == 0 || (var.recovery_window_days >= 7 && var.recovery_window_days <= 30)
    error_message = "Recovery window must be 0 or between 7 and 30."
  }
}

variable "replica_regions" {
  type        = list(string)
  description = "Regions for secret replicas"
  default     = []
}

variable "tags" {
  type        = map(string)
  description = "Additional tags"
  default     = {}
}

variable "create_rotation_lambda" {
  type        = bool
  description = "Create Lambda function for rotation"
  default     = false
}

variable "rotation_type" {
  type        = string
  description = "Rotation type (rds, api-key, custom)"
  default     = "custom"

  validation {
    condition     = contains(["rds", "api-key", "custom"], var.rotation_type)
    error_message = "Rotation type must be rds, api-key, or custom."
  }
}

variable "rds_instance_arn" {
  type        = string
  description = "RDS instance ARN for rotation"
  default     = ""
}

variable "rds_master_username" {
  type        = string
  description = "RDS master username"
  default     = "admin"
}
