##############################################
# Required Variables
##############################################

variable "name_prefix" {
  description = "Prefix for resource naming"
  type        = string
}

variable "queue_name" {
  description = "Name of the SQS queue (without .fifo suffix)"
  type        = string
}

##############################################
# Queue Configuration
##############################################

variable "fifo_queue" {
  description = "Whether this is a FIFO queue"
  type        = bool
  default     = false
}

variable "content_based_deduplication" {
  description = "Enable content-based deduplication for FIFO queues"
  type        = bool
  default     = false
}

variable "message_retention_seconds" {
  description = "Number of seconds SQS retains a message (60-1209600)"
  type        = number
  default     = 345600 # 4 days
  validation {
    condition     = var.message_retention_seconds >= 60 && var.message_retention_seconds <= 1209600
    error_message = "Message retention must be between 60 and 1209600 seconds."
  }
}

variable "visibility_timeout_seconds" {
  description = "Visibility timeout for messages (0-43200)"
  type        = number
  default     = 30
  validation {
    condition     = var.visibility_timeout_seconds >= 0 && var.visibility_timeout_seconds <= 43200
    error_message = "Visibility timeout must be between 0 and 43200 seconds."
  }
}

variable "delay_seconds" {
  description = "Delay seconds for message delivery (0-900)"
  type        = number
  default     = 0
  validation {
    condition     = var.delay_seconds >= 0 && var.delay_seconds <= 900
    error_message = "Delay seconds must be between 0 and 900."
  }
}

variable "receive_wait_time_seconds" {
  description = "Long polling wait time (0-20)"
  type        = number
  default     = 0
  validation {
    condition     = var.receive_wait_time_seconds >= 0 && var.receive_wait_time_seconds <= 20
    error_message = "Receive wait time must be between 0 and 20 seconds."
  }
}

variable "max_message_size" {
  description = "Maximum message size in bytes (1024-262144)"
  type        = number
  default     = 262144
  validation {
    condition     = var.max_message_size >= 1024 && var.max_message_size <= 262144
    error_message = "Max message size must be between 1024 and 262144 bytes."
  }
}

##############################################
# Encryption Configuration
##############################################

variable "enable_encryption" {
  description = "Enable server-side encryption with KMS"
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "KMS key ID or ARN for encryption (null = create new key)"
  type        = string
  default     = null
}

variable "kms_data_key_reuse_seconds" {
  description = "KMS data key reuse period (60-86400)"
  type        = number
  default     = 300
  validation {
    condition     = var.kms_data_key_reuse_seconds >= 60 && var.kms_data_key_reuse_seconds <= 86400
    error_message = "KMS data key reuse period must be between 60 and 86400 seconds."
  }
}

variable "kms_deletion_window_days" {
  description = "KMS key deletion window in days"
  type        = number
  default     = 30
}

##############################################
# Dead Letter Queue Configuration
##############################################

variable "enable_dead_letter_queue" {
  description = "Enable dead letter queue"
  type        = bool
  default     = true
}

variable "max_receive_count" {
  description = "Maximum receives before moving to DLQ"
  type        = number
  default     = 3
}

variable "dlq_message_retention_seconds" {
  description = "Message retention for DLQ (60-1209600)"
  type        = number
  default     = 1209600 # 14 days
  validation {
    condition     = var.dlq_message_retention_seconds >= 60 && var.dlq_message_retention_seconds <= 1209600
    error_message = "DLQ message retention must be between 60 and 1209600 seconds."
  }
}

variable "enable_redrive_allow_policy" {
  description = "Enable redrive allow policy for DLQ"
  type        = bool
  default     = false
}

variable "redrive_permission" {
  description = "Redrive permission (allowAll, denyAll, byQueue)"
  type        = string
  default     = "byQueue"
  validation {
    condition     = contains(["allowAll", "denyAll", "byQueue"], var.redrive_permission)
    error_message = "Redrive permission must be allowAll, denyAll, or byQueue."
  }
}

variable "source_queue_arns" {
  description = "ARNs of source queues allowed to redrive from DLQ"
  type        = list(string)
  default     = []
}

##############################################
# Queue Policy Configuration
##############################################

variable "queue_policy" {
  description = "Custom queue policy JSON (null = use allowed_principals)"
  type        = string
  default     = null
}

variable "allowed_principals" {
  description = "List of AWS principal ARNs allowed to send messages"
  type        = list(string)
  default     = []
}

variable "allow_sns_publish" {
  description = "Allow SNS topics to publish to this queue"
  type        = bool
  default     = false
}

variable "sns_topic_arns" {
  description = "ARNs of SNS topics allowed to publish"
  type        = list(string)
  default     = []
}

##############################################
# CloudWatch Alarms Configuration
##############################################

variable "enable_cloudwatch_alarms" {
  description = "Enable CloudWatch alarms for the queue"
  type        = bool
  default     = true
}

variable "alarm_queue_depth_threshold" {
  description = "Alarm threshold for queue depth"
  type        = number
  default     = 100
}

variable "alarm_message_age_threshold" {
  description = "Alarm threshold for message age in seconds"
  type        = number
  default     = 600
}

variable "alarm_evaluation_periods" {
  description = "Number of evaluation periods for alarms"
  type        = number
  default     = 2
}

variable "alarm_period_seconds" {
  description = "Period in seconds for alarm evaluation"
  type        = number
  default     = 300
}

variable "alarm_actions" {
  description = "List of ARNs for alarm actions (SNS topics)"
  type        = list(string)
  default     = []
}

variable "alarm_ok_actions" {
  description = "List of ARNs for OK actions (SNS topics)"
  type        = list(string)
  default     = []
}

##############################################
# Tagging
##############################################

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}
