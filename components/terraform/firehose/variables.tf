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
  description = "Short name. The delivery stream is named <Environment>-<name> (64 characters at most), its roles <Environment>-<name>-delivery and <Environment>-<name>-source, its log group /aws/kinesisfirehose/<Environment>-<name>"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_.-]{1,40}$", var.name))
    error_message = "name must be 1-40 characters of letters, digits, underscore, period or hyphen."
  }
}

# Source. Cloud Posse's aws-kinesis-firehose-stream only does direct put; the
# Kinesis source is this repo's addition (the data-pipeline template reads its
# streams through Firehose).
variable "kinesis_source_stream_arn" {
  type        = string
  description = "ARN of the Kinesis data stream the delivery stream reads (same region). Null (default) makes a direct put stream (PutRecord/PutRecordBatch). With a stream, the component creates a source role that can only read it"
  default     = null

  validation {
    condition     = var.kinesis_source_stream_arn == null || can(regex("^arn:aws[a-z-]*:kinesis:[a-z0-9-]+:[0-9]{12}:stream/[a-zA-Z0-9_.-]+$", var.kinesis_source_stream_arn))
    error_message = "kinesis_source_stream_arn must be a Kinesis stream ARN (arn:aws:kinesis:<region>:<account>:stream/<name>)."
  }

  validation {
    condition     = var.kinesis_source_stream_arn == null || try(split(":", var.kinesis_source_stream_arn)[3] == var.region, false)
    error_message = "kinesis_source_stream_arn must be in the component's region: Firehose reads only same-region streams."
  }
}

variable "kinesis_source_kms_key_arn" {
  type        = string
  description = "KMS key ARN that encrypts the source stream (the kinesis component's kms_key_id). The source role gets kms:Decrypt on it, scoped to the stream's encryption context. Null for an unencrypted or AWS-managed-key stream; only valid with kinesis_source_stream_arn"
  default     = null

  validation {
    condition     = var.kinesis_source_kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/.+$", var.kinesis_source_kms_key_arn))
    error_message = "kinesis_source_kms_key_arn must be a KMS key ARN (arn:aws:kms:<region>:<account>:key/<id>), not an alias."
  }

  validation {
    condition     = var.kinesis_source_kms_key_arn == null || var.kinesis_source_stream_arn != null
    error_message = "kinesis_source_kms_key_arn needs kinesis_source_stream_arn (a direct put stream has no source stream to decrypt)."
  }
}

variable "server_side_encryption_kms_key_arn" {
  type        = string
  description = "Customer managed KMS key ARN for server-side encryption of a direct put stream (key_type CUSTOMER_MANAGED_CMK). Null encrypts a direct put stream with an AWS owned key. Must be null with kinesis_source_stream_arn: Firehose rejects stream SSE for a Kinesis source, whose data stays encrypted by the source stream's key"
  default     = null

  validation {
    condition     = var.server_side_encryption_kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/.+$", var.server_side_encryption_kms_key_arn))
    error_message = "server_side_encryption_kms_key_arn must be a KMS key ARN (arn:aws:kms:<region>:<account>:key/<id>), not an alias."
  }

  validation {
    condition     = var.server_side_encryption_kms_key_arn == null || var.kinesis_source_stream_arn == null
    error_message = "server_side_encryption_kms_key_arn is only valid for a direct put stream: Firehose rejects server-side encryption with a Kinesis source (kinesis_source_stream_arn)."
  }
}

# Destination: extended_s3 only, as in Cloud Posse's component.
variable "s3_bucket_arn" {
  type        = string
  description = "ARN of the destination S3 bucket (the s3 component's bucket_arn). The delivery role can write to this bucket only"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:s3:::[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.s3_bucket_arn))
    error_message = "s3_bucket_arn must be an S3 bucket ARN (arn:aws:s3:::<bucket>), not a bucket name or an object ARN."
  }
}

variable "s3_prefix" {
  type        = string
  description = "S3 key prefix for delivered objects. May use !{timestamp:...} and !{firehose:random-string} expressions, and with dynamic_partitioning !{partitionKeyFromQuery:<key>} (a key of dynamic_partitioning.jq_queries) and !{partitionKeyFromLambda:<key>} (needs processor_lambda_arn); null uses the Firehose default (YYYY/MM/dd/HH/)"
  default     = null

  validation {
    condition     = var.s3_prefix == null || try(length(var.s3_prefix) <= 1024, false)
    error_message = "s3_prefix must be 1024 characters or fewer."
  }

  validation {
    condition     = !strcontains(coalesce(var.s3_prefix, "-"), "!{firehose:error-output-type}")
    error_message = "s3_prefix cannot use !{firehose:error-output-type}: it is only valid in s3_error_output_prefix."
  }

  validation {
    condition     = !strcontains(coalesce(var.s3_prefix, "-"), "!{partitionKeyFrom") || try(var.dynamic_partitioning.enabled, false)
    error_message = "s3_prefix can use !{partitionKeyFromQuery:...} or !{partitionKeyFromLambda:...} only with dynamic_partitioning enabled."
  }

  # The prefix side of dynamic_partitioning's rules lives here: validations
  # cannot reference each other's variables both ways (a cycle).
  validation {
    condition     = !try(var.dynamic_partitioning.enabled, false) || strcontains(coalesce(var.s3_prefix, "-"), "!{partitionKeyFromQuery:") || strcontains(coalesce(var.s3_prefix, "-"), "!{partitionKeyFromLambda:")
    error_message = "dynamic_partitioning needs an s3_prefix that uses at least one !{partitionKeyFromQuery:<key>} or !{partitionKeyFromLambda:<key>} expression."
  }

  validation {
    condition     = alltrue([for m in regexall("!\\{partitionKeyFromQuery:([^}]*)\\}", coalesce(var.s3_prefix, "-")) : contains(keys(try(var.dynamic_partitioning.jq_queries, {})), trimspace(m[0]))])
    error_message = "Every !{partitionKeyFromQuery:<key>} in s3_prefix must be a key of dynamic_partitioning.jq_queries."
  }

  validation {
    condition     = !strcontains(coalesce(var.s3_prefix, "-"), "!{partitionKeyFromLambda:") || var.processor_lambda_arn != null
    error_message = "!{partitionKeyFromLambda:...} in s3_prefix needs processor_lambda_arn (the Lambda returns the partition keys)."
  }

  validation {
    condition     = var.s3_prefix == null || !strcontains(coalesce(var.s3_prefix, "-"), "!{") || var.s3_error_output_prefix != null
    error_message = "An s3_prefix with !{...} expressions needs s3_error_output_prefix (Firehose rejects the pair otherwise)."
  }
}

variable "s3_error_output_prefix" {
  type        = string
  description = "S3 key prefix for records Firehose fails to deliver or process. With !{...} expressions it must include !{firehose:error-output-type}; null uses the Firehose default"
  default     = null

  validation {
    condition     = var.s3_error_output_prefix == null || try(length(var.s3_error_output_prefix) <= 1024, false)
    error_message = "s3_error_output_prefix must be 1024 characters or fewer."
  }

  validation {
    # One line: Checkov's HCL parser rejects a line that starts with ||.
    condition     = var.s3_error_output_prefix == null || !strcontains(coalesce(var.s3_error_output_prefix, "-"), "!{") || strcontains(coalesce(var.s3_error_output_prefix, "-"), "!{firehose:error-output-type}")
    error_message = "An s3_error_output_prefix with !{...} expressions must include !{firehose:error-output-type}."
  }

  validation {
    condition     = !strcontains(coalesce(var.s3_error_output_prefix, "-"), "!{partitionKeyFrom")
    error_message = "s3_error_output_prefix cannot use !{partitionKeyFromQuery:...} or !{partitionKeyFromLambda:...}: failed records have no partition keys."
  }
}

variable "buffering_size" {
  type        = number
  description = "Buffer size in MiB (1-128) before Firehose writes an object"
  default     = 5

  validation {
    condition     = var.buffering_size >= 1 && var.buffering_size <= 128
    error_message = "buffering_size must be between 1 and 128 MiB."
  }
}

variable "buffering_interval" {
  type        = number
  description = "Buffer interval in seconds (0-900) before Firehose writes an object, whichever of size or interval is reached first"
  default     = 300

  validation {
    condition     = var.buffering_interval >= 0 && var.buffering_interval <= 900
    error_message = "buffering_interval must be between 0 and 900 seconds."
  }
}

variable "compression_format" {
  type        = string
  description = "Compression of delivered objects: UNCOMPRESSED (Cloud Posse's default), GZIP, ZIP, Snappy or HADOOP_SNAPPY. Must be UNCOMPRESSED with data_format_conversion (the Parquet/ORC serializer compresses)"
  default     = "UNCOMPRESSED"

  validation {
    condition     = contains(["UNCOMPRESSED", "GZIP", "ZIP", "Snappy", "HADOOP_SNAPPY"], var.compression_format)
    error_message = "compression_format must be UNCOMPRESSED, GZIP, ZIP, Snappy or HADOOP_SNAPPY."
  }
}

variable "kms_key_arn" {
  type        = string
  description = "Customer managed KMS key ARN that encrypts delivered S3 objects (SSE-KMS) and the delivery log group. The delivery role gets kms:GenerateDataKey and kms:Decrypt on it through S3 only; its policy must allow logs.<region>.amazonaws.com (kms allow_cloudwatch_logs). Cloud Posse's encryption_enabled uses the AWS managed aws/s3 key instead"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/.+$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN (arn:aws:kms:<region>:<account>:key/<id>), not an alias: it is an IAM policy Resource."
  }
}

variable "log_retention_days" {
  type        = number
  description = "Number of days to retain the delivery stream's CloudWatch log group (/aws/kinesisfirehose/<Environment>-<name>)"
  default     = 90

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a CloudWatch Logs retention value (1, 3, 5, 7, 14, 30, 60, 90, ...)."
  }
}

# Record processing, conversion and partitioning. Cloud Posse's
# aws-kinesis-firehose-stream has none of these; the shapes follow
# aws_kinesis_firehose_delivery_stream's extended_s3_configuration blocks.
variable "data_format_conversion" {
  type = object({
    enabled = optional(bool, true)
    # OPENX_JSON (OpenX JSON SerDe) or HIVE_JSON (Hive JSON SerDe)
    input_format = optional(string, "OPENX_JSON")
    open_x_json = optional(object({
      case_insensitive                         = optional(bool, true)
      convert_dots_in_json_keys_to_underscores = optional(bool, false)
      column_to_json_key_mappings              = optional(map(string))
    }), {})
    hive_json_timestamp_formats = optional(list(string))
    # PARQUET or ORC
    output_format = optional(string, "PARQUET")
    # PARQUET: UNCOMPRESSED, GZIP or SNAPPY; ORC: NONE, ZLIB or SNAPPY
    compression = optional(string, "SNAPPY")
    parquet = optional(object({
      enable_dictionary_compression = optional(bool, false)
      block_size_bytes              = optional(number)
      page_size_bytes               = optional(number)
      max_padding_bytes             = optional(number)
      writer_version                = optional(string, "V1")
    }), {})
    schema_configuration = object({
      database_name = string
      table_name    = string
      region        = optional(string)
      version_id    = optional(string, "LATEST")
      catalog_id    = optional(string)
      # The Data Catalog's encryption key when the catalog is encrypted (the
      # glue component's catalog encryption): the delivery role gets
      # kms:Decrypt on it through Glue.
      kms_key_arn = optional(string)
    })
  })
  description = "Convert JSON records to Parquet (default, SNAPPY) or ORC against the schema of a Glue table (schema_configuration: database_name, table_name; region defaults to the component's, catalog_id to this account, version_id to LATEST). The table must exist first. The delivery role gets glue:GetTable/GetTableVersion/GetTableVersions on exactly that catalog, database and table. Needs buffering_size >= 64 and compression_format UNCOMPRESSED (the serializer compresses). Null (default) or enabled = false delivers records as received"
  default     = null

  validation {
    condition     = var.data_format_conversion == null || try(contains(["OPENX_JSON", "HIVE_JSON"], var.data_format_conversion.input_format) && contains(["PARQUET", "ORC"], var.data_format_conversion.output_format), false)
    error_message = "data_format_conversion.input_format must be OPENX_JSON or HIVE_JSON, and output_format PARQUET or ORC."
  }

  validation {
    condition     = var.data_format_conversion == null || try(contains(var.data_format_conversion.output_format == "ORC" ? ["NONE", "ZLIB", "SNAPPY"] : ["UNCOMPRESSED", "GZIP", "SNAPPY"], var.data_format_conversion.compression), false)
    error_message = "data_format_conversion.compression must be UNCOMPRESSED, GZIP or SNAPPY for PARQUET, NONE, ZLIB or SNAPPY for ORC."
  }

  validation {
    condition     = var.data_format_conversion == null || try(contains(["V1", "V2"], var.data_format_conversion.parquet.writer_version), false)
    error_message = "data_format_conversion.parquet.writer_version must be V1 or V2."
  }

  validation {
    condition     = var.data_format_conversion == null || try(trimspace(var.data_format_conversion.schema_configuration.database_name) != "" && trimspace(var.data_format_conversion.schema_configuration.table_name) != "", false)
    error_message = "data_format_conversion.schema_configuration needs a non-empty database_name and table_name."
  }

  validation {
    condition     = var.data_format_conversion == null || try(var.data_format_conversion.schema_configuration.catalog_id == null || can(regex("^[0-9]{12}$", var.data_format_conversion.schema_configuration.catalog_id)), false)
    error_message = "data_format_conversion.schema_configuration.catalog_id must be a 12-digit account ID (null for this account)."
  }

  validation {
    condition     = var.data_format_conversion == null || try(var.data_format_conversion.schema_configuration.region == null || can(regex("^[a-z]{2}(-[a-z]+)+-\\d+$", var.data_format_conversion.schema_configuration.region)), false)
    error_message = "data_format_conversion.schema_configuration.region must be an AWS region name (null for the component's region)."
  }

  validation {
    condition     = var.data_format_conversion == null || try(var.data_format_conversion.schema_configuration.kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/.+$", var.data_format_conversion.schema_configuration.kms_key_arn)), false)
    error_message = "data_format_conversion.schema_configuration.kms_key_arn must be a KMS key ARN (arn:aws:kms:<region>:<account>:key/<id>), not an alias."
  }

  validation {
    condition     = !try(var.data_format_conversion.enabled, false) || var.buffering_size >= 64
    error_message = "data_format_conversion needs buffering_size >= 64 MiB (Firehose's minimum with format conversion)."
  }

  validation {
    condition     = !try(var.data_format_conversion.enabled, false) || var.compression_format == "UNCOMPRESSED"
    error_message = "data_format_conversion needs compression_format UNCOMPRESSED: Firehose rejects S3 compression with format conversion (set data_format_conversion.compression instead)."
  }
}

variable "dynamic_partitioning" {
  type = object({
    enabled        = optional(bool, true)
    retry_duration = optional(number, 300)
    # Partition key -> JQ expression, rendered into one MetadataExtraction
    # processor (JQ-1.6), e.g. { source = ".source" }; the prefix reads a key
    # as !{partitionKeyFromQuery:source}.
    jq_queries = optional(map(string), {})
    # Adds the AppendDelimiterToRecord processor (a newline after each record).
    append_delimiter = optional(bool, false)
  })
  description = "Dynamic partitioning: partition S3 objects by keys extracted from each record with JQ (jq_queries, !{partitionKeyFromQuery:<key>}) or returned by processor_lambda_arn (!{partitionKeyFromLambda:<key>}). retry_duration (0-7200 seconds, default 300) is how long Firehose retries S3 delivery. Needs buffering_size >= 64, and s3_prefix must use at least one partition key. Can only be turned on when the stream is created. Null (default) or enabled = false turns it off"
  default     = null

  validation {
    condition     = var.dynamic_partitioning == null || try(var.dynamic_partitioning.retry_duration >= 0 && var.dynamic_partitioning.retry_duration <= 7200, false)
    error_message = "dynamic_partitioning.retry_duration must be between 0 and 7200 seconds."
  }

  validation {
    condition     = var.dynamic_partitioning == null || try(alltrue([for k, v in var.dynamic_partitioning.jq_queries : can(regex("^[a-zA-Z0-9_]+$", k)) && trimspace(v) != ""]), false)
    error_message = "dynamic_partitioning.jq_queries keys must be letters, digits or underscores, and each needs a non-empty JQ expression."
  }

  validation {
    condition     = !try(var.dynamic_partitioning.enabled, false) || var.buffering_size >= 64
    error_message = "dynamic_partitioning needs buffering_size >= 64 MiB (Firehose's minimum with dynamic partitioning)."
  }
}

variable "processor_lambda_arn" {
  type        = string
  description = "ARN of a Lambda function (the lambda component's function_arn, optionally with a version or alias qualifier) that transforms records before delivery, and may return partition keys for !{partitionKeyFromLambda:...}. The delivery role gets lambda:InvokeFunction and lambda:GetFunctionConfiguration on this ARN and its unqualified form. Null (default) adds no Lambda processor"
  default     = null

  validation {
    condition     = var.processor_lambda_arn == null || can(regex("^arn:aws[a-z-]*:lambda:[a-z0-9-]+:[0-9]{12}:function:[a-zA-Z0-9_-]{1,64}(:[a-zA-Z0-9$_-]{1,128})?$", var.processor_lambda_arn))
    error_message = "processor_lambda_arn must be a Lambda function ARN (arn:aws:lambda:<region>:<account>:function:<name>[:<version or alias>]), not a function name."
  }
}

variable "processor_lambda_config" {
  type = object({
    buffer_size_in_mbs         = optional(number, 1)
    buffer_interval_in_seconds = optional(number, 60)
    number_of_retries          = optional(number, 3)
  })
  description = "Lambda processor settings: BufferSizeInMBs (1-3, default 1), BufferIntervalInSeconds (60-900, default 60) and NumberOfRetries (0-300, default 3). Used only with processor_lambda_arn"
  default     = {}

  validation {
    condition     = var.processor_lambda_config.buffer_size_in_mbs >= 1 && var.processor_lambda_config.buffer_size_in_mbs <= 3
    error_message = "processor_lambda_config.buffer_size_in_mbs must be between 1 and 3 (Lambda's 6 MB payload limit)."
  }

  validation {
    condition     = var.processor_lambda_config.buffer_interval_in_seconds >= 60 && var.processor_lambda_config.buffer_interval_in_seconds <= 900
    error_message = "processor_lambda_config.buffer_interval_in_seconds must be between 60 and 900."
  }

  validation {
    condition     = var.processor_lambda_config.number_of_retries >= 0 && var.processor_lambda_config.number_of_retries <= 300
    error_message = "processor_lambda_config.number_of_retries must be between 0 and 300."
  }
}
