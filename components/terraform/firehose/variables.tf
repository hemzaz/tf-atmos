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
  description = "S3 key prefix for delivered objects. May use !{timestamp:...} and !{firehose:random-string} expressions; null uses the Firehose default (YYYY/MM/dd/HH/). Dynamic partitioning expressions (!{partitionKeyFromQuery:...}, !{partitionKeyFromLambda:...}) are not supported yet"
  default     = null

  validation {
    condition     = var.s3_prefix == null || try(length(var.s3_prefix) <= 1024, false)
    error_message = "s3_prefix must be 1024 characters or fewer."
  }

  validation {
    condition     = var.s3_prefix == null || !strcontains(coalesce(var.s3_prefix, "-"), "!{partitionKeyFrom")
    error_message = "s3_prefix cannot use !{partitionKeyFromQuery:...} or !{partitionKeyFromLambda:...}: dynamic partitioning is not supported by this component yet."
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
    condition = var.s3_error_output_prefix == null || (
      !strcontains(coalesce(var.s3_error_output_prefix, "-"), "!{")
      || strcontains(coalesce(var.s3_error_output_prefix, "-"), "!{firehose:error-output-type}")
    )
    error_message = "An s3_error_output_prefix with !{...} expressions must include !{firehose:error-output-type}."
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
  description = "Compression of delivered objects: UNCOMPRESSED (Cloud Posse's default), GZIP, ZIP, Snappy or HADOOP_SNAPPY"
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
