variable "region" {
  type        = string
  description = "AWS region"
  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-\\d+$", var.region))
    error_message = "The region must be a valid AWS region name (e.g., us-east-1, eu-west-1)."
  }
}

variable "cross_account_role_name" {
  type        = string
  description = "Name of the cross-account IAM role"
}

variable "trusted_account_ids" {
  type        = list(string)
  description = "List of AWS account IDs that are allowed to assume the cross-account role"
  validation {
    condition     = alltrue([for id in var.trusted_account_ids : can(regex("^\\d{12}$", id))])
    error_message = "Each AWS account ID must be a 12-digit number."
  }
}

variable "policy_name" {
  type        = string
  description = "Name of the IAM policy to be attached to the cross-account role"
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to the IAM resources"
  default     = {}
}