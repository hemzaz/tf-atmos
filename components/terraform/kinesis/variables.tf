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
  description = "Short name. The stream is named <Environment>-<name>"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,100}$", var.name))
    error_message = "name must be 1-100 characters of letters, digits, underscore or hyphen (the stream name, <Environment>-<name>, is capped at 128 by AWS)."
  }
}

variable "stream_mode" {
  type        = string
  description = "Capacity mode: ON_DEMAND or PROVISIONED"
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "PROVISIONED"], var.stream_mode)
    error_message = "stream_mode must be ON_DEMAND or PROVISIONED."
  }
}

variable "shard_count" {
  type        = number
  description = "Number of shards. Required (and must be > 0) when stream_mode is PROVISIONED; must be left null for ON_DEMAND, which manages its own capacity"
  default     = null

  validation {
    condition     = var.stream_mode == "PROVISIONED" ? (var.shard_count != null && var.shard_count > 0) : var.shard_count == null
    error_message = "shard_count must be set to a positive number when stream_mode is PROVISIONED, and must be null (unset) when stream_mode is ON_DEMAND."
  }
}

variable "retention_period" {
  type        = number
  description = "Number of hours records are retained in the stream"
  default     = 24

  validation {
    condition     = var.retention_period >= 24 && var.retention_period <= 8760
    error_message = "retention_period must be between 24 and 8760 hours (1 to 365 days)."
  }
}

variable "kms_key_id" {
  type        = string
  description = "KMS key ARN that encrypts the stream. Must be a full key ARN, not an alias or bare key ID: it is used verbatim as an IAM policy Resource element in the reader_policy/writer_policy outputs, and IAM Resource elements only match ARNs. Encryption is always KMS; there is no unencrypted option"

  validation {
    condition     = can(regex("^arn:aws[a-zA-Z-]*:kms:[a-z0-9-]+:\\d{12}:key/[a-zA-Z0-9-]+$", var.kms_key_id))
    error_message = "kms_key_id must be a full KMS key ARN (arn:aws:kms:<region>:<account-id>:key/<key-id>), not an alias or bare key ID: it is used directly as an IAM policy Resource element in reader_policy/writer_policy, which only match ARNs."
  }
}

variable "shard_level_metrics" {
  type        = list(string)
  description = "Shard-level CloudWatch metrics to enable (enhanced monitoring). Empty list disables shard-level metrics"
  default     = []
  nullable    = false

  validation {
    condition = alltrue([
      for m in var.shard_level_metrics : contains([
        "IncomingBytes",
        "IncomingRecords",
        "OutgoingBytes",
        "OutgoingRecords",
        "WriteProvisionedThroughputExceeded",
        "ReadProvisionedThroughputExceeded",
        "IteratorAgeMilliseconds",
      ], m)
    ])
    error_message = "shard_level_metrics may only contain: IncomingBytes, IncomingRecords, OutgoingBytes, OutgoingRecords, WriteProvisionedThroughputExceeded, ReadProvisionedThroughputExceeded, IteratorAgeMilliseconds."
  }
}

variable "enforce_consumer_deletion" {
  type        = bool
  description = "Allow the stream to be destroyed even if it still has registered enhanced fan-out consumers"
  default     = false
}

variable "additional_policy_json" {
  type        = string
  description = "An additional IAM policy document (JSON, {Version, Statement}) whose Statement entries are merged into this stream's writer_policy output - typically another kinesis instance's own reader_policy or writer_policy output, wired in via !terraform.state. Lets one consumer that both reads one stream and writes another (e.g. a Lambda function whose custom_policy input accepts only one policy document) get a single combined grant, without Atmos ever having to read two components' live state into one YAML value (which !terraform.state alone cannot do, and an Atmos Go template - atmos.Component - can, but only by requiring live state at describe/validate time too, breaking `atmos describe stacks`/`atmos validate stacks` for the whole stack before first apply). Null (the default) adds nothing"
  default     = null
  nullable    = true
}

variable "consumers" {
  type = map(object({
    enabled = optional(bool, true)
  }))
  description = "Enhanced fan-out consumers to register on the stream (aws_kinesis_stream_consumer), keyed by the AWS-registered consumer name (1-128 characters). Each entry's enabled toggles that one consumer independently of the stream itself"
  default     = {}
  nullable    = false
}
