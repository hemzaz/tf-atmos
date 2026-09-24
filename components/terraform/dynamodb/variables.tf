variable "region" {
  type        = string
  description = "AWS region"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-\\d+$", var.region))
    error_message = "The region must be a valid AWS region name (e.g., us-east-1, eu-west-1)."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to resources; must include Environment (used in the default table name)"

  validation {
    condition     = trimspace(lookup(var.tags, "Environment", "")) != ""
    error_message = "tags must include a non-empty Environment value."
  }
}

variable "enabled" {
  type        = bool
  description = "Set to false to prevent the component from creating any resources"
  default     = true
}

# Inputs below mirror Cloud Posse's aws-dynamodb component (same names and
# meanings). Trimmed: autoscaler_*, replicas and import_table. See README.md.

variable "name" {
  type        = string
  description = "Short table name. The table is named <Environment>-<name> unless table_name is set"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_.-]{1,200}$", var.name))
    error_message = "name must be 1-200 characters of letters, digits, underscore, hyphen or period."
  }
}

variable "table_name" {
  type        = string
  description = "Exact table name. Overrides the <Environment>-<name> default"
  default     = null

  validation {
    condition     = var.table_name == null || can(regex("^[a-zA-Z0-9_.-]{3,255}$", var.table_name))
    error_message = "table_name must be 3-255 characters of letters, digits, underscore, hyphen or period."
  }
}

variable "billing_mode" {
  type        = string
  description = "PAY_PER_REQUEST or PROVISIONED. PROVISIONED uses read_capacity and write_capacity (no autoscaling)"
  default     = "PAY_PER_REQUEST"

  validation {
    condition     = contains(["PAY_PER_REQUEST", "PROVISIONED"], var.billing_mode)
    error_message = "billing_mode must be PAY_PER_REQUEST or PROVISIONED."
  }
}

variable "read_capacity" {
  type        = number
  description = "Provisioned read capacity units for the table and every GSI that sets none. Ignored for PAY_PER_REQUEST"
  default     = 5

  validation {
    condition     = var.read_capacity >= 1
    error_message = "read_capacity must be at least 1."
  }
}

variable "write_capacity" {
  type        = number
  description = "Provisioned write capacity units for the table and every GSI that sets none. Ignored for PAY_PER_REQUEST"
  default     = 5

  validation {
    condition     = var.write_capacity >= 1
    error_message = "write_capacity must be at least 1."
  }
}

variable "hash_key" {
  type        = string
  description = "Partition (hash) key attribute name"

  validation {
    condition     = length(var.hash_key) > 0 && length(var.hash_key) <= 255
    error_message = "hash_key must be 1-255 characters."
  }
}

variable "hash_key_type" {
  type        = string
  description = "Hash key type: S, N or B (string, number, binary)"
  default     = "S"

  validation {
    condition     = contains(["S", "N", "B"], var.hash_key_type)
    error_message = "hash_key_type must be S, N or B."
  }
}

variable "range_key" {
  type        = string
  description = "Sort (range) key attribute name. Empty for a hash-only table"
  default     = ""
}

variable "range_key_type" {
  type        = string
  description = "Range key type: S, N or B (string, number, binary)"
  default     = "S"

  validation {
    condition     = contains(["S", "N", "B"], var.range_key_type)
    error_message = "range_key_type must be S, N or B."
  }
}

variable "dynamodb_attributes" {
  type = list(object({
    name = string
    type = string
  }))
  description = "Attributes besides the hash and range keys; declare only those an index uses as a key"
  default     = []

  validation {
    condition     = alltrue([for a in var.dynamodb_attributes : contains(["S", "N", "B"], a.type)])
    error_message = "Every dynamodb_attributes type must be S, N or B."
  }
}

variable "global_secondary_index_map" {
  type = list(object({
    name               = string
    hash_key           = string
    range_key          = optional(string)
    projection_type    = optional(string, "ALL")
    non_key_attributes = optional(list(string))
    read_capacity      = optional(number)
    write_capacity     = optional(number)
  }))
  description = "Global secondary indexes. Their key attributes must be declared in dynamodb_attributes (or be the table keys)"
  default     = []

  validation {
    condition     = alltrue([for i in var.global_secondary_index_map : contains(["ALL", "KEYS_ONLY", "INCLUDE"], i.projection_type)])
    error_message = "Every global_secondary_index_map projection_type must be ALL, KEYS_ONLY or INCLUDE."
  }
}

variable "local_secondary_index_map" {
  type = list(object({
    name               = string
    range_key          = string
    projection_type    = optional(string, "ALL")
    non_key_attributes = optional(list(string))
  }))
  description = "Local secondary indexes (share the table hash key). Their range keys must be declared in dynamodb_attributes"
  default     = []

  validation {
    condition     = alltrue([for i in var.local_secondary_index_map : contains(["ALL", "KEYS_ONLY", "INCLUDE"], i.projection_type)])
    error_message = "Every local_secondary_index_map projection_type must be ALL, KEYS_ONLY or INCLUDE."
  }
}

variable "server_side_encryption_kms_key_arn" {
  type        = string
  description = "ARN of the customer managed KMS key that encrypts the table (stacks pass !terraform.state kms/main .key_arn)"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/.+$", var.server_side_encryption_kms_key_arn))
    error_message = "server_side_encryption_kms_key_arn must be a KMS key ARN (arn:aws:kms:<region>:<account>:key/<id>); the AWS owned and AWS managed keys are not accepted."
  }
}

variable "point_in_time_recovery_enabled" {
  type        = bool
  description = "Enable point-in-time recovery (continuous backups)"
  default     = true
}

variable "deletion_protection_enabled" {
  type        = bool
  description = "Enable table deletion protection"
  default     = false
}

variable "streams_enabled" {
  type        = bool
  description = "Enable DynamoDB Streams"
  default     = false
}

variable "stream_view_type" {
  type        = string
  description = "What a stream record holds: KEYS_ONLY, NEW_IMAGE, OLD_IMAGE or NEW_AND_OLD_IMAGES. Required when streams_enabled"
  default     = ""

  validation {
    condition     = contains(["", "KEYS_ONLY", "NEW_IMAGE", "OLD_IMAGE", "NEW_AND_OLD_IMAGES"], var.stream_view_type)
    error_message = "stream_view_type must be empty or one of KEYS_ONLY, NEW_IMAGE, OLD_IMAGE, NEW_AND_OLD_IMAGES."
  }

  validation {
    condition     = !var.streams_enabled || var.stream_view_type != ""
    error_message = "stream_view_type is required when streams_enabled is true."
  }
}

variable "ttl_enabled" {
  type        = bool
  description = "Enable Time to Live on ttl_attribute"
  default     = false
}

variable "ttl_attribute" {
  type        = string
  description = "Attribute holding the expiry epoch. Required when ttl_enabled"
  default     = ""

  validation {
    condition     = !var.ttl_enabled || var.ttl_attribute != ""
    error_message = "ttl_attribute is required when ttl_enabled is true."
  }
}
