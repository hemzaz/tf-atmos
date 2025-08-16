##################################################
# AWS Secrets Manager Component Variables
##################################################

variable "secrets_enabled" {
  type        = bool
  description = "Enable/disable the secrets manager component"
  default     = true
}

variable "context_name" {
  type        = string
  description = "The context name to use as the first segment of the secret path (application, service, or system name)"

  validation {
    condition     = var.context_name != ""
    error_message = "The context_name variable is required and cannot be empty."
  }
}

variable "secrets" {
  type        = any
  description = <<-EOT
    Map of secrets to be created. Each secret can have the following attributes:
      - name: The name of the secret (will be used as the last segment of the path)
      - description: Description of the secret (defaults to 'Managed by Terraform')
      - policy: JSON IAM policy to attach to the secret (optional)
      - path: Additional path segments to insert between environment and name (optional)
      - kms_key_id: KMS key ID to use for encryption (defaults to default_kms_key_id)
      - secret_data: The secret data to store (optional, mutually exclusive with generate_random_password)
      - rotation_lambda_arn: ARN of the Lambda function for rotation (optional)
      - rotation_days: Days between automatic rotation (defaults to default_rotation_days)
      - rotation_automatically: Whether to enable automatic rotation (defaults to default_rotation_automatically)
      - recovery_window_in_days: Window for recovery before permanent deletion (defaults to default_recovery_window_in_days)
      - generate_random_password: Whether to generate a random password for this secret (defaults to false)
  EOT
  default     = {}

  validation {
    condition = alltrue([
      for k, v in var.secrets :
      lookup(v, "secret_data", null) == null || lookup(v, "generate_random_password", false) == false
    ])
    error_message = "secret_data and generate_random_password cannot both be specified for the same secret."
  }
}

variable "default_kms_key_id" {
  type        = string
  description = "Default KMS key ID to use for encrypting secrets if not specified at the secret level"
  default     = null
}

variable "default_rotation_days" {
  type        = number
  description = "Default number of days between automatic rotation if not specified at the secret level"
  default     = 30

  validation {
    condition     = var.default_rotation_days >= 1 && var.default_rotation_days <= 365
    error_message = "default_rotation_days must be between 1 and 365."
  }
}

variable "default_rotation_automatically" {
  type        = bool
  description = "Default setting for automatic rotation if not specified at the secret level"
  default     = false
}

variable "default_recovery_window_in_days" {
  type        = number
  description = "Default recovery window in days before permanent deletion if not specified at the secret level"
  default     = 30

  validation {
    condition     = var.default_recovery_window_in_days >= 0 && var.default_recovery_window_in_days <= 30
    error_message = "default_recovery_window_in_days must be between 0 and 30."
  }
}

# Random password generation parameters
variable "random_password_length" {
  type        = number
  description = "Length of generated random passwords"
  default     = 32

  validation {
    condition     = var.random_password_length >= 8
    error_message = "random_password_length must be at least 8 characters."
  }
}

variable "random_password_special" {
  type        = bool
  description = "Whether to include special characters in random passwords"
  default     = true
}

variable "random_password_override_special" {
  type        = string
  description = "Supply your own list of special characters for random password generation"
  default     = "!#$%&*()-_=+[]{}<>:?"
}

variable "random_password_min_lower" {
  type        = number
  description = "Minimum number of lowercase characters in random passwords"
  default     = 5
}

variable "random_password_min_upper" {
  type        = number
  description = "Minimum number of uppercase characters in random passwords"
  default     = 5
}

variable "random_password_min_numeric" {
  type        = number
  description = "Minimum number of numeric characters in random passwords"
  default     = 5
}

variable "random_password_min_special" {
  type        = number
  description = "Minimum number of special characters in random passwords"
  default     = 5
}