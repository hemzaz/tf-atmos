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
  description = "Short name. The role (<Environment>-<name>-glue), security configuration and each crawler, job and trigger are named <Environment>-<name>[-<key>]. The catalog database reuses the same string with hyphens replaced by underscores (Glue database names allow only lowercase letters, digits and underscores)"

  validation {
    condition     = can(regex("^[a-z0-9-]{1,40}$", var.name))
    error_message = "name must be 1-40 characters of lowercase letters, digits or hyphens."
  }
}

variable "kms_key_arn" {
  type        = string
  description = "Customer managed KMS key ARN. Used for the security configuration (CloudWatch Logs, job bookmarks, S3 output), job script objects, the optional Data Catalog encryption settings, and the role's own KMS grant"

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
  description = "Default location (an s3:// URI) for tables in the database"
  default     = ""

  validation {
    condition     = var.location_uri == "" || startswith(var.location_uri, "s3://")
    error_message = "location_uri must be empty or an s3:// URI."
  }
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

variable "enable_data_catalog_encryption" {
  type        = bool
  description = "Set the account's Data Catalog encryption settings (metadata SSE-KMS and connection password encryption, both with kms_key_arn). One setting per account and region: enable it on exactly one glue instance per account/region"
  default     = false
}

variable "tables" {
  type = map(object({
    description           = optional(string)
    table_type            = optional(string, "EXTERNAL_TABLE")
    parameters            = optional(map(string), {})
    location              = string
    input_format          = string
    output_format         = string
    serialization_library = string
    ser_de_parameters     = optional(map(string), {})
    compressed            = optional(bool, false)
    columns = list(object({
      name    = string
      type    = string
      comment = optional(string)
    }))
    partition_keys = optional(list(object({
      name    = string
      type    = string
      comment = optional(string)
    })), [])
  }))
  description = "Catalog tables to create in this instance's database, keyed by table name. With parameters[\"projection.enabled\"] = \"true\" and no storage.location.template, the component derives one (<location><key>=$${<key>}/...) from the partition keys"
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for k in keys(var.tables) : can(regex("^[a-z0-9_]{1,255}$", k))])
    error_message = "Table keys (the table names) must be lowercase letters, digits or underscores."
  }

  validation {
    condition     = alltrue([for t in values(var.tables) : can(regex("^s3://[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]/(.*/)?$", t.location))])
    error_message = "Every table location must be an s3:// URI ending in /."
  }

  validation {
    condition     = alltrue([for t in values(var.tables) : length(t.columns) > 0])
    error_message = "Every table must define at least one column."
  }
}

variable "crawlers" {
  type = map(object({
    description  = optional(string)
    schedule     = optional(string)
    table_prefix = optional(string)
    # Passed through jsonencode() to the crawler's `configuration` argument
    # (a JSON string), e.g. { Version = 1.0, Grouping = { TableGroupingPolicy = "CombineCompatibleSchemas" } }.
    configuration = optional(any)
    s3_targets = optional(list(object({
      path       = string
      exclusions = optional(list(string), [])
    })), [])
    # Keys of var.tables, crawled as one catalog target (keeps the schema and
    # partitions of tables this instance defines up to date).
    catalog_tables = optional(list(string), [])
    schema_change_policy = optional(object({
      delete_behavior = string
      update_behavior = string
    }))
  }))
  description = "Crawlers against this instance's database, keyed by a short suffix (each is named <Environment>-<name>-<key>). Each sets either s3_targets or catalog_tables (keys of tables), not both. All crawlers share this component's role and security configuration"
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for c in values(var.crawlers) : (length(c.s3_targets) > 0) != (length(c.catalog_tables) > 0)])
    error_message = "Every crawler must set either s3_targets or catalog_tables (not both, not neither)."
  }

  validation {
    condition     = alltrue(flatten([for c in values(var.crawlers) : [for t in c.s3_targets : startswith(t.path, "s3://")]]))
    error_message = "Every s3_targets path must be an s3:// URI."
  }

  validation {
    condition     = alltrue(flatten([for c in values(var.crawlers) : [for t in c.catalog_tables : contains(keys(var.tables), t)]]))
    error_message = "Every catalog_tables entry must be a key of var.tables."
  }

  validation {
    condition = alltrue([
      for c in values(var.crawlers) : length(c.catalog_tables) == 0 || try(c.schema_change_policy.delete_behavior, "") == "LOG"
    ])
    error_message = "A crawler with catalog_tables must set schema_change_policy.delete_behavior = LOG (AWS requirement for catalog targets)."
  }

  validation {
    condition = alltrue([
      for c in values(var.crawlers) : c.schema_change_policy == null || (
        contains(["LOG", "DELETE_FROM_DATABASE", "DEPRECATE_IN_DATABASE"], try(c.schema_change_policy.delete_behavior, "")) &&
        contains(["LOG", "UPDATE_IN_DATABASE"], try(c.schema_change_policy.update_behavior, ""))
      )
    ])
    error_message = "schema_change_policy.delete_behavior must be LOG, DELETE_FROM_DATABASE or DEPRECATE_IN_DATABASE, and update_behavior must be LOG or UPDATE_IN_DATABASE."
  }
}

variable "assets_bucket_name" {
  type        = string
  description = "Bucket the component uploads job scripts to (scripts/<Environment>-<name>/<job>.py) and that jobs use as --TempDir (temporary/<Environment>-<name>/). Required when jobs is non-empty"
  default     = ""

  validation {
    condition     = var.assets_bucket_name == "" || can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.assets_bucket_name))
    error_message = "assets_bucket_name must be empty or a valid S3 bucket name."
  }
}

variable "s3_read_buckets" {
  type        = list(string)
  description = "Additional bucket names the role may read (ListBucket, GetObject), e.g. job inputs. Buckets of crawler s3_targets and table locations are added automatically"
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for b in var.s3_read_buckets : can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", b))])
    error_message = "s3_read_buckets entries must be S3 bucket names (not ARNs or URIs)."
  }
}

variable "s3_write_buckets" {
  type        = list(string)
  description = "Bucket names the role may write (GetObject, PutObject, DeleteObject), e.g. job outputs"
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for b in var.s3_write_buckets : can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", b))])
    error_message = "s3_write_buckets entries must be S3 bucket names (not ARNs or URIs)."
  }
}

variable "jobs" {
  type = map(object({
    description         = optional(string)
    script              = string
    glue_version        = optional(string, "5.0")
    worker_type         = optional(string, "G.1X")
    number_of_workers   = optional(number, 2)
    timeout             = optional(number, 60)
    max_retries         = optional(number, 0)
    max_concurrent_runs = optional(number, 1)
    job_bookmark_option = optional(string, "job-bookmark-enable")
    default_arguments   = optional(map(string), {})
  }))
  description = "Spark ETL jobs (glueetl, Python 3), keyed by a short suffix (each is named <Environment>-<name>-<key>). script is the job's PySpark source, uploaded by the component to assets_bucket_name. default_arguments are merged over the component's defaults (--TempDir, --enable-glue-datacatalog, metrics, continuous logging, --job-bookmark-option)"
  default     = {}
  nullable    = false

  validation {
    condition     = length(var.jobs) == 0 || var.assets_bucket_name != ""
    error_message = "assets_bucket_name is required when jobs is non-empty (job scripts are uploaded there)."
  }

  validation {
    condition     = alltrue([for j in values(var.jobs) : contains(["G.025X", "G.1X", "G.2X", "G.4X", "G.8X", "Z.2X"], j.worker_type)])
    error_message = "worker_type must be one of G.025X, G.1X, G.2X, G.4X, G.8X, Z.2X."
  }

  validation {
    condition     = alltrue([for j in values(var.jobs) : contains(["job-bookmark-enable", "job-bookmark-disable", "job-bookmark-pause"], j.job_bookmark_option)])
    error_message = "job_bookmark_option must be job-bookmark-enable, job-bookmark-disable or job-bookmark-pause."
  }

  validation {
    condition     = alltrue([for j in values(var.jobs) : j.number_of_workers >= 2 && j.timeout >= 1 && j.max_retries >= 0 && j.max_concurrent_runs >= 1])
    error_message = "number_of_workers must be >= 2, timeout >= 1, max_retries >= 0 and max_concurrent_runs >= 1."
  }
}

variable "triggers" {
  type = map(object({
    description       = optional(string)
    type              = string
    schedule          = optional(string)
    enabled           = optional(bool, true)
    start_on_creation = optional(bool, true)
    actions = list(object({
      job       = optional(string)
      crawler   = optional(string)
      arguments = optional(map(string))
      timeout   = optional(number)
    }))
    predicate = optional(object({
      logical = optional(string, "AND")
      conditions = list(object({
        job     = optional(string)
        crawler = optional(string)
        state   = string
      }))
    }))
  }))
  description = "Glue triggers, keyed by a short suffix (each is named <Environment>-<name>-<key>). Actions and predicate conditions name this instance's own jobs/crawlers by their key (exactly one of job or crawler). A condition's state is a job run state (SUCCEEDED, STOPPED, FAILED, TIMEOUT) or a crawl state (SUCCEEDED, CANCELLED, FAILED)"
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for t in values(var.triggers) : contains(["SCHEDULED", "CONDITIONAL", "ON_DEMAND"], t.type)])
    error_message = "Trigger type must be SCHEDULED, CONDITIONAL or ON_DEMAND."
  }

  validation {
    condition     = alltrue([for t in values(var.triggers) : (t.type == "SCHEDULED") == (t.schedule != null)])
    error_message = "schedule is required for (and only for) SCHEDULED triggers."
  }

  validation {
    condition     = alltrue([for t in values(var.triggers) : (t.type == "CONDITIONAL") == (t.predicate != null)])
    error_message = "predicate is required for (and only for) CONDITIONAL triggers."
  }

  validation {
    condition = alltrue(flatten([
      for t in values(var.triggers) : concat(
        [length(t.actions) > 0],
        [for a in t.actions : (a.job != null) != (a.crawler != null)],
        [for c in try(t.predicate.conditions, []) : (c.job != null) != (c.crawler != null)],
      )
    ]))
    error_message = "Every trigger needs at least one action, and every action and condition sets exactly one of job or crawler."
  }

  validation {
    condition = alltrue(flatten([
      for t in values(var.triggers) : concat(
        [for a in t.actions : a.job == null || contains(keys(var.jobs), coalesce(a.job, "-"))],
        [for a in t.actions : a.crawler == null || contains(keys(var.crawlers), coalesce(a.crawler, "-"))],
        [for c in try(t.predicate.conditions, []) : c.job == null || contains(keys(var.jobs), coalesce(c.job, "-"))],
        [for c in try(t.predicate.conditions, []) : c.crawler == null || contains(keys(var.crawlers), coalesce(c.crawler, "-"))],
      )
    ]))
    error_message = "Trigger actions and conditions must reference keys of var.jobs / var.crawlers."
  }

  validation {
    condition = alltrue(flatten([
      for t in values(var.triggers) : concat(
        [contains(["AND", "ANY"], try(t.predicate.logical, "AND"))],
        [for c in try(t.predicate.conditions, []) : c.job != null ? contains(["SUCCEEDED", "STOPPED", "FAILED", "TIMEOUT"], c.state) : contains(["SUCCEEDED", "CANCELLED", "FAILED"], c.state)],
      )
    ]))
    error_message = "predicate.logical must be AND or ANY; job conditions use SUCCEEDED/STOPPED/FAILED/TIMEOUT and crawler conditions SUCCEEDED/CANCELLED/FAILED."
  }
}
