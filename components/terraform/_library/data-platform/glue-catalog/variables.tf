variable "database_name" {
  type        = string
  description = "Glue catalog database name"

  validation {
    condition     = can(regex("^[a-z0-9_]+$", var.database_name))
    error_message = "Database name must contain only lowercase letters, numbers, and underscores."
  }
}

variable "database_description" {
  type        = string
  description = "Database description"
  default     = "Managed by Terraform"
}

variable "catalog_id" {
  type        = string
  description = "Catalog ID (AWS account ID)"
  default     = null
}

variable "tables" {
  type = map(object({
    description = optional(string)
    table_type  = optional(string, "EXTERNAL_TABLE")
    owner       = optional(string, "hadoop")
    parameters  = optional(map(string), {})
    storage_descriptor = optional(object({
      location      = optional(string)
      input_format  = optional(string, "org.apache.hadoop.mapred.TextInputFormat")
      output_format = optional(string, "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat")
      compressed    = optional(bool, false)
      ser_de_info = optional(object({
        name                  = optional(string)
        serialization_library = optional(string, "org.apache.hadoop.hive.serde2.lazy.LazySimpleSerDe")
        parameters            = optional(map(string), {})
      }))
      columns = optional(list(object({
        name    = string
        type    = string
        comment = optional(string)
      })), [])
      sort_columns = optional(list(object({
        column     = string
        sort_order = number
      })), [])
      skewed_info = optional(object({
        skewed_column_names               = optional(list(string), [])
        skewed_column_value_location_maps = optional(map(string), {})
        skewed_column_values              = optional(list(string), [])
      }))
    }))
    partition_keys = optional(list(object({
      name    = string
      type    = string
      comment = optional(string)
    })), [])
  }))
  description = "Map of Glue catalog tables"
  default     = {}
}

variable "crawlers" {
  type = map(object({
    description = optional(string)
    schedule    = optional(string)
    s3_targets = optional(list(object({
      path                = string
      exclusions          = optional(list(string), [])
      sample_size         = optional(number)
      connection_name     = optional(string)
      event_queue_arn     = optional(string)
      dlq_event_queue_arn = optional(string)
    })), [])
    jdbc_targets = optional(list(object({
      connection_name = string
      path            = string
      exclusions      = optional(list(string), [])
    })), [])
    dynamodb_targets = optional(list(object({
      path      = string
      scan_all  = optional(bool, true)
      scan_rate = optional(number)
    })), [])
    schema_change_policy = optional(object({
      delete_behavior = optional(string, "LOG")
      update_behavior = optional(string, "LOG")
    }))
    recrawl_policy = optional(object({
      recrawl_behavior = optional(string, "CRAWL_EVERYTHING")
    }))
    enable_lineage = optional(bool, false)
    configuration  = optional(string)
  }))
  description = "Map of Glue crawlers"
  default     = {}

  validation {
    condition = alltrue(flatten([
      for k, v in var.crawlers : v.schema_change_policy == null ? [true] : [
        contains(["LOG", "DELETE_FROM_DATABASE", "DEPRECATE_IN_DATABASE"], v.schema_change_policy.delete_behavior),
        contains(["LOG", "UPDATE_IN_DATABASE"], v.schema_change_policy.update_behavior),
      ]
    ]))
    error_message = "schema_change_policy.delete_behavior must be LOG|DELETE_FROM_DATABASE|DEPRECATE_IN_DATABASE and update_behavior LOG|UPDATE_IN_DATABASE."
  }

  validation {
    condition = alltrue([
      for k, v in var.crawlers : v.recrawl_policy == null ? true : contains(["CRAWL_EVERYTHING", "CRAWL_NEW_FOLDERS_ONLY", "CRAWL_EVENT_MODE"], v.recrawl_policy.recrawl_behavior)
    ])
    error_message = "recrawl_policy.recrawl_behavior must be CRAWL_EVERYTHING, CRAWL_NEW_FOLDERS_ONLY, or CRAWL_EVENT_MODE."
  }
}

variable "s3_data_locations" {
  type        = list(string)
  description = "List of S3 locations for crawler access"
  default     = []
}

variable "create_schema_registry" {
  type        = bool
  description = "Create Glue Schema Registry"
  default     = false
}

variable "schemas" {
  type = map(object({
    data_format       = optional(string, "AVRO")
    compatibility     = optional(string, "BACKWARD")
    schema_definition = string
    description       = optional(string)
  }))
  description = "Map of schema definitions (requires create_schema_registry = true)"
  default     = {}

  validation {
    condition     = length(var.schemas) == 0 || var.create_schema_registry
    error_message = "schemas require create_schema_registry = true."
  }

  validation {
    condition = alltrue([
      for k, v in var.schemas :
      contains(["AVRO", "JSON", "PROTOBUF"], v.data_format)
    ])
    error_message = "Data format must be AVRO, JSON, or PROTOBUF."
  }

  validation {
    condition = alltrue([
      for k, v in var.schemas :
      contains(["NONE", "DISABLED", "BACKWARD", "BACKWARD_ALL", "FORWARD", "FORWARD_ALL", "FULL", "FULL_ALL"], v.compatibility)
    ])
    error_message = "Invalid compatibility mode."
  }
}

variable "data_quality_rulesets" {
  type = map(object({
    table_name  = string
    ruleset     = string
    description = optional(string)
  }))
  description = "Map of data quality rulesets"
  default     = {}
}

variable "enable_monitoring" {
  type        = bool
  description = "Enable CloudWatch alarms"
  default     = true
}

variable "alarm_actions" {
  type        = list(string)
  description = "List of ARNs for alarm actions (SNS topics)"
  default     = []
}

variable "tags" {
  type        = map(string)
  description = "Additional tags for all resources"
  default     = {}
}
