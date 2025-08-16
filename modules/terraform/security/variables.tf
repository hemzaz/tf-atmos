# Security module variables

# Common variables (passed through to common module)
variable "namespace" {
  type        = string
  description = "Namespace for resource naming"
}

variable "environment" {
  type        = string
  description = "Environment name (dev, staging, prod)"
}

variable "stage" {
  type        = string
  description = "Stage/instance of the environment"
  default     = "01"
}

variable "component_name" {
  type        = string
  description = "Name of the component"
}

variable "region" {
  type        = string
  description = "AWS region"
}

variable "project_name" {
  type        = string
  description = "Name of the project"
  default     = "infrastructure"
}

variable "cost_center" {
  type        = string
  description = "Cost center for billing"
  default     = "infrastructure"
}

variable "owner" {
  type        = string
  description = "Owner/team responsible"
  default     = "platform-team"
}

variable "additional_tags" {
  type        = map(string)
  description = "Additional tags to apply"
  default     = {}
}

variable "data_classification" {
  type        = string
  description = "Data classification level"
  default     = "internal"
}

variable "compliance_frameworks" {
  type        = list(string)
  description = "List of compliance frameworks"
  default     = []
}

variable "backup_required" {
  type        = bool
  description = "Whether backup is required"
  default     = true
}

# KMS Key Configuration
variable "create_kms_key" {
  type        = bool
  description = "Whether to create a KMS key"
  default     = true
}

variable "kms_key_usage" {
  type        = string
  description = "Intended use of the KMS key"
  default     = "ENCRYPT_DECRYPT"

  validation {
    condition     = contains(["ENCRYPT_DECRYPT", "SIGN_VERIFY"], var.kms_key_usage)
    error_message = "KMS key usage must be either ENCRYPT_DECRYPT or SIGN_VERIFY."
  }
}

variable "kms_key_spec" {
  type        = string
  description = "Key spec for the KMS key"
  default     = "SYMMETRIC_DEFAULT"

  validation {
    condition = contains([
      "SYMMETRIC_DEFAULT",
      "RSA_2048",
      "RSA_3072",
      "RSA_4096",
      "ECC_NIST_P256",
      "ECC_NIST_P384",
      "ECC_NIST_P521",
      "ECC_SECG_P256K1"
    ], var.kms_key_spec)
    error_message = "Invalid KMS key spec."
  }
}

variable "kms_key_deletion_window" {
  type        = number
  description = "KMS key deletion window in days"
  default     = 30

  validation {
    condition     = var.kms_key_deletion_window >= 7 && var.kms_key_deletion_window <= 30
    error_message = "KMS key deletion window must be between 7 and 30 days."
  }
}

variable "enable_key_rotation" {
  type        = bool
  description = "Enable automatic key rotation"
  default     = true
}

variable "enable_multi_region_key" {
  type        = bool
  description = "Create a multi-region KMS key"
  default     = false
}

variable "kms_key_purpose" {
  type        = string
  description = "Purpose of the KMS key for naming"
  default     = "encryption"
}

variable "existing_kms_key_arn" {
  type        = string
  description = "ARN of existing KMS key to use instead of creating one"
  default     = ""
}

# KMS Service Permissions
variable "enable_s3_permissions" {
  type        = bool
  description = "Enable S3 service permissions for KMS key"
  default     = false
}

variable "enable_rds_permissions" {
  type        = bool
  description = "Enable RDS service permissions for KMS key"
  default     = false
}

variable "enable_eks_permissions" {
  type        = bool
  description = "Enable EKS service permissions for KMS key"
  default     = false
}

variable "additional_kms_policy_statements" {
  type = list(object({
    sid       = string
    effect    = string
    principals = object({
      type        = string
      identifiers = list(string)
    })
    actions   = list(string)
    resources = list(string)
    condition = optional(map(map(list(string))), {})
  }))
  description = "Additional policy statements for KMS key"
  default     = []
}

# Security Group Configuration
variable "create_security_group" {
  type        = bool
  description = "Whether to create a security group"
  default     = false
}

variable "vpc_id" {
  type        = string
  description = "VPC ID for security group"
  default     = ""
}

variable "security_group_description" {
  type        = string
  description = "Description for the security group"
  default     = "Security group managed by Terraform"
}

variable "ingress_rules" {
  type = list(object({
    description      = string
    from_port        = number
    to_port          = number
    protocol         = string
    cidr_blocks      = optional(list(string), [])
    ipv6_cidr_blocks = optional(list(string), [])
    prefix_list_ids  = optional(list(string), [])
    security_groups  = optional(list(string), [])
    self             = optional(bool, false)
  }))
  description = "List of ingress rules"
  default     = []
}

variable "egress_rules" {
  type = list(object({
    description      = string
    from_port        = number
    to_port          = number
    protocol         = string
    cidr_blocks      = optional(list(string), [])
    ipv6_cidr_blocks = optional(list(string), [])
    prefix_list_ids  = optional(list(string), [])
    security_groups  = optional(list(string), [])
    self             = optional(bool, false)
  }))
  description = "List of egress rules"
  default = [
    {
      description = "All outbound traffic"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]
}

# IAM Role Configuration
variable "create_service_role" {
  type        = bool
  description = "Whether to create a service role"
  default     = false
}

variable "trusted_services" {
  type        = list(string)
  description = "List of AWS services that can assume the role"
  default     = []
}

variable "trusted_principals" {
  type        = list(string)
  description = "List of AWS principals that can assume the role"
  default     = []
}

variable "managed_policy_arns" {
  type        = list(string)
  description = "List of managed policy ARNs to attach to the role"
  default     = []
}

variable "max_session_duration" {
  type        = number
  description = "Maximum session duration in seconds"
  default     = 3600

  validation {
    condition     = var.max_session_duration >= 3600 && var.max_session_duration <= 43200
    error_message = "Max session duration must be between 3600 and 43200 seconds."
  }
}

variable "iam_path" {
  type        = string
  description = "Path for IAM resources"
  default     = "/"
}

# Custom IAM Policy
variable "create_custom_policy" {
  type        = bool
  description = "Whether to create a custom IAM policy"
  default     = false
}

variable "custom_policy_statements" {
  type = list(object({
    sid       = optional(string)
    effect    = string
    actions   = list(string)
    resources = list(string)
    condition = optional(map(map(list(string))), {})
  }))
  description = "Custom policy statements"
  default     = []
}

# CloudWatch Logs Configuration
variable "create_log_group" {
  type        = bool
  description = "Whether to create a CloudWatch log group"
  default     = false
}

variable "log_group_prefix" {
  type        = string
  description = "Prefix for log group name"
  default     = "security"
}

variable "log_retention_days" {
  type        = number
  description = "Log retention in days"
  default     = 30

  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention must be a valid CloudWatch value."
  }
}

# S3 Bucket Policy Configuration
variable "create_s3_bucket_policy" {
  type        = bool
  description = "Whether to create S3 bucket policy document"
  default     = false
}

variable "s3_bucket_name" {
  type        = string
  description = "S3 bucket name for policy"
  default     = ""
}

variable "deny_cross_account_access" {
  type        = bool
  description = "Deny cross-account access to S3 bucket"
  default     = true
}

# WAF Configuration
variable "create_waf_web_acl" {
  type        = bool
  description = "Whether to create a WAF Web ACL"
  default     = false
}

variable "waf_scope" {
  type        = string
  description = "WAF scope (REGIONAL or CLOUDFRONT)"
  default     = "REGIONAL"

  validation {
    condition     = contains(["REGIONAL", "CLOUDFRONT"], var.waf_scope)
    error_message = "WAF scope must be REGIONAL or CLOUDFRONT."
  }
}

variable "enable_rate_limiting" {
  type        = bool
  description = "Enable rate limiting in WAF"
  default     = true
}

variable "rate_limit_per_5min" {
  type        = number
  description = "Rate limit requests per 5 minutes per IP"
  default     = 2000

  validation {
    condition     = var.rate_limit_per_5min >= 100 && var.rate_limit_per_5min <= 20000000
    error_message = "Rate limit must be between 100 and 20,000,000."
  }
}

variable "blocked_countries" {
  type        = list(string)
  description = "List of country codes to block"
  default     = []

  validation {
    condition = alltrue([
      for code in var.blocked_countries : 
      can(regex("^[A-Z]{2}$", code))
    ])
    error_message = "Country codes must be 2-letter uppercase codes."
  }
}