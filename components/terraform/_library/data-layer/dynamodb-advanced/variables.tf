variable "name_prefix" {
  type        = string
  description = "Prefix for resource naming"
}

variable "environment" {
  type        = string
  description = "Environment name"
}

variable "table_name" {
  type        = string
  description = "DynamoDB table name (will be prefixed with name_prefix-environment)"
  default     = "table"
}

variable "billing_mode" {
  type        = string
  description = "Billing mode: PAY_PER_REQUEST or PROVISIONED"
  default     = "PAY_PER_REQUEST"
  validation {
    condition     = contains(["PAY_PER_REQUEST", "PROVISIONED"], var.billing_mode)
    error_message = "billing_mode must be PAY_PER_REQUEST or PROVISIONED"
  }
}

variable "read_capacity" {
  type        = number
  description = "Read capacity units (for PROVISIONED mode)"
  default     = 5
}

variable "write_capacity" {
  type        = number
  description = "Write capacity units (for PROVISIONED mode)"
  default     = 5
}

variable "hash_key" {
  type        = string
  description = "Hash key (partition key) attribute name"
  default     = "id"
}

variable "hash_key_type" {
  type        = string
  description = "Hash key attribute type: S (string), N (number), or B (binary)"
  default     = "S"
}

variable "range_key" {
  type        = string
  description = "Range key (sort key) attribute name"
  default     = null
}

variable "range_key_type" {
  type        = string
  description = "Range key attribute type: S, N, or B"
  default     = "S"
}

variable "attributes" {
  type = list(object({
    name = string
    type = string
  }))
  description = "Additional attributes for GSI/LSI"
  default     = []
}

variable "global_secondary_indexes" {
  type = list(object({
    name            = string
    hash_key        = string
    range_key       = optional(string)
    projection_type = optional(string, "ALL")
    read_capacity   = optional(number, 5)
    write_capacity  = optional(number, 5)
  }))
  description = "Global secondary indexes"
  default     = []
}

variable "local_secondary_indexes" {
  type = list(object({
    name            = string
    range_key       = string
    projection_type = optional(string, "ALL")
  }))
  description = "Local secondary indexes"
  default     = []
}

variable "enable_autoscaling" {
  type        = bool
  description = "Enable auto-scaling for provisioned capacity"
  default     = true
}

variable "autoscaling_read_min" {
  type        = number
  description = "Minimum read capacity for auto-scaling"
  default     = 5
}

variable "autoscaling_read_max" {
  type        = number
  description = "Maximum read capacity for auto-scaling"
  default     = 100
}

variable "autoscaling_read_target" {
  type        = number
  description = "Target utilization % for read auto-scaling"
  default     = 70
}

variable "autoscaling_write_min" {
  type        = number
  description = "Minimum write capacity for auto-scaling"
  default     = 5
}

variable "autoscaling_write_max" {
  type        = number
  description = "Maximum write capacity for auto-scaling"
  default     = 100
}

variable "autoscaling_write_target" {
  type        = number
  description = "Target utilization % for write auto-scaling"
  default     = 70
}

variable "enable_streams" {
  type        = bool
  description = "Enable DynamoDB Streams"
  default     = false
}

variable "stream_view_type" {
  type        = string
  description = "Stream view type: KEYS_ONLY, NEW_IMAGE, OLD_IMAGE, NEW_AND_OLD_IMAGES"
  default     = "NEW_AND_OLD_IMAGES"
}

variable "enable_point_in_time_recovery" {
  type        = bool
  description = "Enable point-in-time recovery"
  default     = true
}

variable "enable_encryption" {
  type        = bool
  description = "Enable encryption at rest"
  default     = true
}

variable "kms_key_arn" {
  type        = string
  description = "KMS key ARN for encryption (default AWS managed key if null)"
  default     = null
}

variable "enable_ttl" {
  type        = bool
  description = "Enable Time To Live"
  default     = false
}

variable "ttl_attribute_name" {
  type        = string
  description = "TTL attribute name"
  default     = "ttl"
}

variable "enable_global_tables" {
  type        = bool
  description = "Enable global tables (multi-region)"
  default     = false
}

variable "replica_regions" {
  type        = list(string)
  description = "List of regions for global table replicas"
  default     = []
}

variable "enable_deletion_protection" {
  type        = bool
  description = "Enable deletion protection"
  default     = true
}

variable "table_class" {
  type        = string
  description = "Table class: STANDARD or STANDARD_INFREQUENT_ACCESS"
  default     = "STANDARD"
}

variable "tags" {
  type        = map(string)
  description = "Additional tags"
  default     = {}
}
