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
  description = "Tags to apply to resources; must include Environment (used in resource names)"

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

variable "name" {
  type        = string
  description = "Short name. The crawler role, security configuration and each crawler are named <Environment>-<name>[-<crawler key>]. The catalog database reuses the same string with hyphens replaced by underscores (Glue database names allow only lowercase letters, digits and underscores)"

  validation {
    condition     = can(regex("^[a-z0-9-]{1,40}$", var.name))
    error_message = "name must be 1-40 characters of lowercase letters, digits or hyphens."
  }
}

variable "kms_key_arn" {
  type        = string
  description = "Customer managed KMS key ARN. Used for the security configuration's CloudWatch/job-bookmark/S3 encryption and for the crawler role's own kms:Decrypt/Encrypt/GenerateDataKey grant"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/.+$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN (arn:aws:kms:<region>:<account>:key/<id>)."
  }
}

variable "database_description" {
  type        = string
  description = "Description of the Glue catalog database"
  default     = ""
}

variable "location_uri" {
  type        = string
  description = "Default location (e.g. an s3:// URI) for tables in the database"
  default     = ""
}

variable "create_table_default_permissions" {
  type = list(object({
    principal = object({
      data_lake_principal_identifier = string
    })
    permissions = list(string)
  }))
  description = "Default table permissions granted on the database (aws_glue_catalog_database create_table_default_permission blocks)"
  default     = []
  nullable    = false
}

variable "crawlers" {
  type = map(object({
    description  = optional(string)
    schedule     = optional(string)
    table_prefix = optional(string)
    # Passed through jsonencode() to the crawler's `configuration` argument
    # (a JSON string), e.g. { Version = 1.0, Grouping = { TableGroupingPolicy = "CombineCompatibleSchemas" } }.
    configuration = optional(map(any))
    s3_targets = list(object({
      path       = string
      exclusions = optional(list(string), [])
    }))
    schema_change_policy = optional(object({
      delete_behavior = string
      update_behavior = string
    }))
  }))
  description = "Crawlers to create against this instance's own catalog database, keyed by a short suffix (each crawler is named <Environment>-<name>-<key>). All crawlers share this component's own crawler role and security configuration"
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for c in values(var.crawlers) : length(c.s3_targets) > 0])
    error_message = "Every crawler must set at least one s3_targets entry."
  }

  validation {
    condition = alltrue([
      for c in values(var.crawlers) : c.schema_change_policy == null || (
        contains(["LOG", "DELETE_FROM_DATABASE", "DEPRECATE_IN_DATABASE"], c.schema_change_policy.delete_behavior) &&
        contains(["LOG", "UPDATE_IN_DATABASE"], c.schema_change_policy.update_behavior)
      )
    ])
    error_message = "schema_change_policy.delete_behavior must be LOG, DELETE_FROM_DATABASE or DEPRECATE_IN_DATABASE, and update_behavior must be LOG or UPDATE_IN_DATABASE."
  }
}
