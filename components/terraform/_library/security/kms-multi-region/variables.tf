##############################################
# Required Variables
##############################################

variable "name_prefix" {
  type        = string
  description = "Prefix for resource names (tenant-environment-stage)"

  validation {
    condition     = length(var.name_prefix) > 0 && length(var.name_prefix) <= 50
    error_message = "The name_prefix must be between 1 and 50 characters."
  }
}

##############################################
# Key Configuration
##############################################

variable "description" {
  type        = string
  description = "Description of the KMS key purpose"
  default     = "Managed by Terraform"
}

variable "key_spec" {
  type        = string
  description = "Key specification (SYMMETRIC_DEFAULT, RSA_2048, RSA_3072, RSA_4096, ECC_NIST_P256, ECC_NIST_P384, ECC_NIST_P521, ECC_SECG_P256K1)"
  default     = "SYMMETRIC_DEFAULT"

  validation {
    condition = contains([
      "SYMMETRIC_DEFAULT", "RSA_2048", "RSA_3072", "RSA_4096",
      "ECC_NIST_P256", "ECC_NIST_P384", "ECC_NIST_P521", "ECC_SECG_P256K1"
    ], var.key_spec)
    error_message = "Invalid key_spec."
  }
}

variable "key_usage" {
  type        = string
  description = "Key usage (ENCRYPT_DECRYPT, SIGN_VERIFY)"
  default     = "ENCRYPT_DECRYPT"

  validation {
    condition     = contains(["ENCRYPT_DECRYPT", "SIGN_VERIFY"], var.key_usage)
    error_message = "Key usage must be ENCRYPT_DECRYPT or SIGN_VERIFY."
  }
}

variable "customer_master_key_spec" {
  type        = string
  description = "Deprecated. Use key_spec instead"
  default     = null
}

variable "is_multi_region" {
  type        = bool
  description = "Enable multi-region key replication"
  default     = false
}

##############################################
# Rotation Configuration
##############################################

variable "enable_key_rotation" {
  type        = bool
  description = "Enable automatic key rotation (annually)"
  default     = true
}

variable "rotation_period_in_days" {
  type        = number
  description = "Key rotation period in days (90-2560)"
  default     = 365

  validation {
    condition     = var.rotation_period_in_days >= 90 && var.rotation_period_in_days <= 2560
    error_message = "Rotation period must be between 90 and 2560 days."
  }
}

##############################################
# Deletion Configuration
##############################################

variable "deletion_window_in_days" {
  type        = number
  description = "KMS key deletion window (7-30 days)"
  default     = 30

  validation {
    condition     = var.deletion_window_in_days >= 7 && var.deletion_window_in_days <= 30
    error_message = "Deletion window must be between 7 and 30 days."
  }
}

##############################################
# Key Policy
##############################################

variable "key_policy" {
  type        = string
  description = "Custom key policy JSON. If not provided, default policy will be created"
  default     = ""
}

variable "enable_default_policy" {
  type        = bool
  description = "Enable default key policy (grants root account full access)"
  default     = true
}

variable "key_administrators" {
  type        = list(string)
  description = "List of IAM ARNs for key administrators"
  default     = []
}

variable "key_users" {
  type        = list(string)
  description = "List of IAM ARNs for key users (encrypt/decrypt)"
  default     = []
}

variable "key_service_users" {
  type        = list(string)
  description = "List of AWS service principals that can use the key"
  default     = []
}

##############################################
# Alias Configuration
##############################################

variable "alias_name" {
  type        = string
  description = "KMS key alias (without alias/ prefix). If empty, uses name_prefix"
  default     = ""
}

variable "create_alias" {
  type        = bool
  description = "Create KMS key alias"
  default     = true
}

##############################################
# Multi-Region Configuration
##############################################

variable "replica_regions" {
  type        = list(string)
  description = "List of AWS regions for key replicas (requires is_multi_region=true)"
  default     = []
}

variable "replica_deletion_window_in_days" {
  type        = number
  description = "Deletion window for replica keys"
  default     = 30

  validation {
    condition     = var.replica_deletion_window_in_days >= 7 && var.replica_deletion_window_in_days <= 30
    error_message = "Replica deletion window must be between 7 and 30 days."
  }
}

##############################################
# Grants Configuration
##############################################

variable "grants" {
  type = list(object({
    name              = string
    grantee_principal = string
    operations        = list(string)
    constraints = optional(object({
      encryption_context_equals = optional(map(string))
      encryption_context_subset = optional(map(string))
    }))
  }))
  description = "List of KMS grants to create"
  default     = []
}

##############################################
# Tagging
##############################################

variable "tags" {
  type        = map(string)
  description = "Additional tags for resources"
  default     = {}
}
