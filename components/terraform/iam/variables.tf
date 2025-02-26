variable "region" {
  type        = string
  description = "AWS region"
}

variable "cross_account_role_name" {
  type        = string
  description = "Name of the cross-account IAM role"
}

variable "trusted_account_ids" {
  type        = list(string)
  description = "List of AWS account IDs that are allowed to assume the cross-account role"
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