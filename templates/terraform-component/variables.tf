# Template: Terraform Component Variables File
# This template follows the best practices outlined in CLAUDE.md
# Replace placeholder values and comments with your actual implementation

variable "region" {
  type        = string
  description = "AWS region"
}

variable "assume_role_arn" {
  type        = string
  description = "ARN of the IAM role to assume"
  default     = null
}

variable "enabled" {
  type        = bool
  description = "Whether to create the resources. Set to false to avoid creating resources"
  default     = true
}

variable "name" {
  type        = string
  description = "Name for this resource"
  validation {
    condition     = length(var.name) > 0 && length(var.name) <= 64
    error_message = "The name must be between 1 and 64 characters in length."
  }
}

variable "description" {
  type        = string
  description = "Description for this resource"
  default     = "Managed by Terraform"
}

# FEATURE FLAGS
# Examples of feature flags for your component

variable "enable_logging" {
  type        = bool
  description = "Whether to enable CloudWatch logging"
  default     = true
}

variable "enable_monitoring" {
  type        = bool
  description = "Whether to enable CloudWatch monitoring"
  default     = true
}

# CONFIGURATION PARAMETERS
# Examples of configuration parameters for your component

variable "example_parameter_string" {
  type        = string
  description = "Example string parameter"
  default     = "default-value"
  validation {
    condition     = length(var.example_parameter_string) > 0
    error_message = "The parameter cannot be empty."
  }
}

variable "example_parameter_number" {
  type        = number
  description = "Example number parameter"
  default     = 5
  validation {
    condition     = var.example_parameter_number > 0
    error_message = "The parameter must be greater than 0."
  }
}

variable "example_parameter_list" {
  type        = list(string)
  description = "Example list parameter"
  default     = []
}

variable "example_parameter_map" {
  type        = map(string)
  description = "Example map parameter"
  default     = {}
}

# INTEGRATION PARAMETERS
# Examples of parameters for integration with other components

variable "example_dependency_id" {
  type        = string
  description = "ID of a resource from another component"
  default     = null
}

variable "example_dependency_arns" {
  type        = list(string)
  description = "List of ARNs from another component"
  default     = []
}

# SECURITY PARAMETERS
# Examples of security-related parameters

variable "kms_key_id" {
  type        = string
  description = "KMS key ID for encryption"
  default     = null
}

variable "log_retention_days" {
  type        = number
  description = "Number of days to retain CloudWatch logs"
  default     = 30
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "The log retention days must be one of the allowed values: 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653."
  }
}

variable "tags" {
  type        = map(string)
  description = "A map of tags to add to all resources"
  default     = {}
}