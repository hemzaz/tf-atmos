################################################################################
# General Configuration
################################################################################

variable "name" {
  description = "Name of the ECR repository"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+(?:[._-][a-z0-9]+)*$", var.name))
    error_message = "Repository name must be lowercase, alphanumeric, and can contain hyphens, underscores, or periods."
  }
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

################################################################################
# Repository Configuration
################################################################################

variable "image_tag_mutability" {
  description = "Image tag mutability setting (MUTABLE, IMMUTABLE)"
  type        = string
  default     = "MUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "Image tag mutability must be MUTABLE or IMMUTABLE."
  }
}

variable "force_delete" {
  description = "Force deletion of repository even if it contains images"
  type        = bool
  default     = false
}

################################################################################
# Image Scanning Configuration
################################################################################

variable "enable_scan_on_push" {
  description = "Enable automatic image scanning on push"
  type        = bool
  default     = true
}

variable "scan_type" {
  description = "Scanning type (BASIC, ENHANCED)"
  type        = string
  default     = "ENHANCED"

  validation {
    condition     = contains(["BASIC", "ENHANCED"], var.scan_type)
    error_message = "Scan type must be BASIC or ENHANCED."
  }
}

variable "scan_frequency" {
  description = "Scanning frequency for enhanced scanning (SCAN_ON_PUSH, CONTINUOUS_SCAN, MANUAL)"
  type        = string
  default     = "SCAN_ON_PUSH"

  validation {
    condition     = contains(["SCAN_ON_PUSH", "CONTINUOUS_SCAN", "MANUAL"], var.scan_frequency)
    error_message = "Scan frequency must be SCAN_ON_PUSH, CONTINUOUS_SCAN, or MANUAL."
  }
}

variable "scan_filters" {
  description = "List of image tag patterns to scan"
  type        = list(string)
  default     = ["*"]
}

################################################################################
# Encryption Configuration
################################################################################

variable "encryption_type" {
  description = "Encryption type (AES256, KMS)"
  type        = string
  default     = "KMS"

  validation {
    condition     = contains(["AES256", "KMS"], var.encryption_type)
    error_message = "Encryption type must be AES256 or KMS."
  }
}

variable "kms_key_id" {
  description = "KMS key ID for encryption (uses AWS managed key if not specified)"
  type        = string
  default     = null
}

################################################################################
# Lifecycle Policy Configuration
################################################################################

variable "enable_lifecycle_policy" {
  description = "Enable lifecycle policy for image cleanup"
  type        = bool
  default     = true
}

variable "lifecycle_policy_rules" {
  description = "Custom lifecycle policy rules (JSON). If not provided, uses default rules."
  type        = string
  default     = null
}

variable "untagged_image_retention_days" {
  description = "Number of days to retain untagged images (default lifecycle policy)"
  type        = number
  default     = 7

  validation {
    condition     = var.untagged_image_retention_days >= 1
    error_message = "Retention days must be at least 1."
  }
}

variable "tagged_image_count_limit" {
  description = "Maximum number of tagged images to retain (default lifecycle policy)"
  type        = number
  default     = 30

  validation {
    condition     = var.tagged_image_count_limit >= 1
    error_message = "Image count limit must be at least 1."
  }
}

################################################################################
# Repository Policy Configuration
################################################################################

variable "repository_policy" {
  description = "Repository policy JSON. If not provided, creates a default policy based on cross_account_principals."
  type        = string
  default     = null
}

variable "cross_account_principals" {
  description = "List of AWS account IDs or ARNs for cross-account access"
  type        = list(string)
  default     = []
}

variable "cross_account_actions" {
  description = "List of ECR actions to allow for cross-account access"
  type        = list(string)
  default = [
    "ecr:GetDownloadUrlForLayer",
    "ecr:BatchGetImage",
    "ecr:BatchCheckLayerAvailability",
    "ecr:DescribeImages",
    "ecr:DescribeRepositories"
  ]
}

################################################################################
# Replication Configuration
################################################################################

variable "enable_replication" {
  description = "Enable cross-region replication"
  type        = bool
  default     = false
}

variable "replication_destinations" {
  description = "List of replication destinations"
  type = list(object({
    region      = string
    registry_id = optional(string)
  }))
  default = []
}

variable "replication_filters" {
  description = "List of repository filters for replication"
  type = list(object({
    filter      = string
    filter_type = string # PREFIX_MATCH
  }))
  default = []
}

################################################################################
# CloudWatch Metrics Configuration
################################################################################

variable "enable_cloudwatch_metrics" {
  description = "Enable CloudWatch metrics for the repository"
  type        = bool
  default     = true
}

################################################################################
# Pull Through Cache Configuration
################################################################################

variable "enable_pull_through_cache" {
  description = "Enable pull through cache for external registries"
  type        = bool
  default     = false
}

variable "upstream_registry_url" {
  description = "URL of upstream registry for pull through cache"
  type        = string
  default     = null
}

variable "credential_arn" {
  description = "ARN of Secrets Manager secret containing upstream registry credentials"
  type        = string
  default     = null
}
