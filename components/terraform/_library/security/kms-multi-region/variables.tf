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

  validation {
    condition     = var.customer_master_key_spec == null || contains(["SYMMETRIC_DEFAULT", "RSA_2048", "RSA_3072", "RSA_4096", "ECC_NIST_P256", "ECC_NIST_P384", "ECC_NIST_P521", "ECC_SECG_P256K1", "HMAC_224", "HMAC_256", "HMAC_384", "HMAC_512"], var.customer_master_key_spec)
    error_message = "Invalid customer_master_key_spec."
  }
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

  validation {
    condition     = var.key_policy == "" || can(jsondecode(var.key_policy))
    error_message = "key_policy must be empty or a valid JSON document."
  }
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

variable "allow_cloudwatch_logs" {
  type        = bool
  description = "Let CloudWatch Logs (logs.<region>.amazonaws.com) encrypt log groups of this account and region with the key, scoped by kms:EncryptionContext:aws:logs:arn"
  default     = false
}

variable "allow_eventbridge" {
  type        = bool
  description = "Let EventBridge (events.amazonaws.com) use the key for event buses and archives of this account and region (scoped by kms:EncryptionContext:aws:events:event-bus:arn; DescribeKey by aws:SourceAccount) and for rules publishing to this account's SNS topics encrypted with it (kms:EncryptionContext:aws:sns:topicArn only: SNS does not support aws:SourceAccount/aws:SourceArn in the KMS policy for EventBridge-to-encrypted topics)"
  default     = false
}

variable "allow_cloudwatch_alarms" {
  type        = bool
  description = "Let CloudWatch alarms (cloudwatch.amazonaws.com) publish to this account's SNS topics encrypted with the key (kms:GenerateDataKey*, kms:Decrypt), scoped by aws:SourceAccount and kms:EncryptionContext:aws:sns:topicArn"
  default     = false
}

variable "allow_cloudtrail" {
  type        = bool
  description = "Let CloudTrail (cloudtrail.amazonaws.com) encrypt this account's trail log files with the key (kms:GenerateDataKey*, scoped by kms:EncryptionContext:aws:cloudtrail:arn) and describe it, both limited to this account's trails in this region by aws:SourceArn"
  default     = false
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

  validation {
    condition     = length(var.replica_regions) == 0 || var.is_multi_region
    error_message = "replica_regions requires is_multi_region = true."
  }
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
