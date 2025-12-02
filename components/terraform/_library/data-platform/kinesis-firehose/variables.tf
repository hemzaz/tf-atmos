variable "name_prefix" {
  type        = string
  description = "Prefix for resource names"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.name_prefix))
    error_message = "Name prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "destination" {
  type        = string
  description = "Delivery destination (extended_s3, opensearch, redshift)"

  validation {
    condition     = contains(["extended_s3", "opensearch", "redshift"], var.destination)
    error_message = "Destination must be extended_s3, opensearch, or redshift."
  }
}

variable "kinesis_source_stream_arn" {
  type        = string
  description = "Source Kinesis stream ARN (null for direct PUT)"
  default     = null
}

variable "s3_bucket_arn" {
  type        = string
  description = "Destination S3 bucket ARN"
}

variable "s3_prefix" {
  type        = string
  description = "S3 object prefix"
  default     = "data/"
}

variable "s3_error_prefix" {
  type        = string
  description = "S3 error output prefix"
  default     = "errors/"
}

variable "s3_compression_format" {
  type        = string
  description = "Compression format (UNCOMPRESSED, GZIP, ZIP, Snappy, HADOOP_SNAPPY)"
  default     = "GZIP"

  validation {
    condition     = contains(["UNCOMPRESSED", "GZIP", "ZIP", "Snappy", "HADOOP_SNAPPY"], var.s3_compression_format)
    error_message = "Invalid compression format."
  }
}

variable "buffer_size_mb" {
  type        = number
  description = "Buffer size in MB (1-128)"
  default     = 5

  validation {
    condition     = var.buffer_size_mb >= 1 && var.buffer_size_mb <= 128
    error_message = "Buffer size must be between 1 and 128 MB."
  }
}

variable "buffer_interval_seconds" {
  type        = number
  description = "Buffer interval in seconds (60-900)"
  default     = 300

  validation {
    condition     = var.buffer_interval_seconds >= 60 && var.buffer_interval_seconds <= 900
    error_message = "Buffer interval must be between 60 and 900 seconds."
  }
}

variable "enable_transformation" {
  type        = bool
  description = "Enable Lambda data transformation"
  default     = false
}

variable "transformation_lambda_arn" {
  type        = string
  description = "Lambda function ARN for transformation"
  default     = ""
}

variable "kms_key_arn" {
  type        = string
  description = "KMS key ARN for encryption"
  default     = null
}

variable "enable_s3_backup" {
  type        = bool
  description = "Enable S3 backup for all records"
  default     = false
}

variable "backup_s3_bucket_arn" {
  type        = string
  description = "Backup S3 bucket ARN"
  default     = ""
}

variable "backup_s3_prefix" {
  type        = string
  description = "Backup S3 prefix"
  default     = "backup/"
}

variable "enable_parquet_conversion" {
  type        = bool
  description = "Enable JSON to Parquet conversion"
  default     = false
}

variable "glue_database_name" {
  type        = string
  description = "Glue database name for schema"
  default     = ""
}

variable "glue_table_name" {
  type        = string
  description = "Glue table name for schema"
  default     = ""
}

variable "opensearch_domain_arn" {
  type        = string
  description = "OpenSearch domain ARN"
  default     = ""
}

variable "opensearch_index_name" {
  type        = string
  description = "OpenSearch index name"
  default     = "firehose"
}

variable "opensearch_type_name" {
  type        = string
  description = "OpenSearch type name"
  default     = "_doc"
}

variable "opensearch_index_rotation" {
  type        = string
  description = "OpenSearch index rotation period"
  default     = "NoRotation"

  validation {
    condition     = contains(["NoRotation", "OneHour", "OneDay", "OneWeek", "OneMonth"], var.opensearch_index_rotation)
    error_message = "Invalid index rotation period."
  }
}

variable "redshift_cluster_jdbcurl" {
  type        = string
  description = "Redshift cluster JDBC URL"
  default     = ""
  sensitive   = true
}

variable "redshift_username" {
  type        = string
  description = "Redshift username"
  default     = ""
  sensitive   = true
}

variable "redshift_password" {
  type        = string
  description = "Redshift password"
  default     = ""
  sensitive   = true
}

variable "redshift_table_name" {
  type        = string
  description = "Redshift table name"
  default     = ""
}

variable "redshift_copy_options" {
  type        = string
  description = "Redshift COPY command options"
  default     = "JSON 'auto'"
}

variable "redshift_table_columns" {
  type        = string
  description = "Redshift table column list"
  default     = ""
}

variable "enable_cloudwatch_logs" {
  type        = bool
  description = "Enable CloudWatch Logs"
  default     = true
}

variable "log_retention_days" {
  type        = number
  description = "CloudWatch log retention in days"
  default     = 7

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Invalid log retention period."
  }
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
