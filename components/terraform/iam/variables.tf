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

  validation {
    condition     = can(regex("^[\\w+=,.@-]{1,64}$", var.cross_account_role_name))
    error_message = "cross_account_role_name must be 1-64 characters of alphanumerics or +=,.@_-."
  }
}

variable "trusted_account_ids" {
  type        = list(string)
  description = "List of AWS account IDs that are allowed to assume the cross-account role"
  validation {
    condition     = length(var.trusted_account_ids) > 0 && alltrue([for id in var.trusted_account_ids : can(regex("^\\d{12}$", id))])
    error_message = "Each AWS account ID must be a 12-digit number."
  }
}

variable "policy_name" {
  type        = string
  description = "Name of the IAM policy to be attached to the cross-account role"

  validation {
    # 128 minus the "-resource-management" suffix appended in resource-management-policy.tf
    condition     = can(regex("^[\\w+=,.@-]{1,108}$", var.policy_name))
    error_message = "policy_name must be 1-108 characters of alphanumerics or +=,.@_-."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to the IAM resources"
  default     = {}
}

# Resource-Specific Permissions (Least Privilege)
variable "managed_s3_bucket_arns" {
  type        = list(string)
  description = "List of S3 bucket ARNs that the role can manage"
  default     = null

  validation {
    condition = var.managed_s3_bucket_arns == null || alltrue([
      for arn in var.managed_s3_bucket_arns : can(regex("^arn:aws:s3:::[a-z0-9.-]+$", arn))
    ])
    error_message = "Each S3 bucket ARN must be valid (e.g., arn:aws:s3:::bucket-name)."
  }
}

variable "managed_dynamodb_table_arns" {
  type        = list(string)
  description = "List of DynamoDB table ARNs that the role can manage"
  default     = null

  validation {
    condition = var.managed_dynamodb_table_arns == null || alltrue([
      for arn in var.managed_dynamodb_table_arns : can(regex("^arn:aws:dynamodb:", arn))
    ])
    error_message = "Each DynamoDB table ARN must be valid."
  }
}

variable "managed_sns_topic_arns" {
  type        = list(string)
  description = "List of SNS topic ARNs that the role can publish to"
  default     = null

  validation {
    condition = var.managed_sns_topic_arns == null || alltrue([
      for arn in var.managed_sns_topic_arns : can(regex("^arn:aws:sns:", arn))
    ])
    error_message = "Each SNS topic ARN must be valid."
  }
}

variable "log_group_arns" {
  type        = list(string)
  description = "List of CloudWatch Log Group ARNs that the role can write to"
  default     = null

  validation {
    condition = var.log_group_arns == null || alltrue([
      for arn in var.log_group_arns : can(regex("^arn:aws:logs:", arn))
    ])
    error_message = "Each log group ARN must be valid."
  }
}

variable "allowed_cloudwatch_namespaces" {
  type        = list(string)
  description = "List of CloudWatch namespaces the role can write metrics to"
  default     = ["AWS/Lambda", "AWS/EC2", "Custom"]

  validation {
    condition     = length(var.allowed_cloudwatch_namespaces) > 0
    error_message = "At least one CloudWatch namespace must be specified."
  }
}

variable "account_id" {
  type        = string
  description = "AWS Account ID for resource ARN construction"

  validation {
    condition     = can(regex("^\\d{12}$", var.account_id))
    error_message = "Account ID must be a 12-digit number."
  }
}

variable "environment" {
  type        = string
  description = "Environment name (dev, staging, prod)"

  validation {
    condition     = contains(["dev", "development", "staging", "stage", "prod", "production"], lower(var.environment))
    error_message = "Environment must be one of: dev, development, staging, stage, prod, production."
  }
}