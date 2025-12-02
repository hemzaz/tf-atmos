##############################################
# Required Variables
##############################################

variable "name_prefix" {
  description = "Prefix for resource naming"
  type        = string
}

variable "topic_name" {
  description = "Name of the SNS topic (without .fifo suffix)"
  type        = string
}

##############################################
# Topic Configuration
##############################################

variable "display_name" {
  description = "Display name for the SNS topic"
  type        = string
  default     = null
}

variable "fifo_topic" {
  description = "Whether this is a FIFO topic"
  type        = bool
  default     = false
}

variable "content_based_deduplication" {
  description = "Enable content-based deduplication for FIFO topics"
  type        = bool
  default     = false
}

variable "delivery_policy" {
  description = "SNS delivery policy JSON"
  type        = string
  default     = null
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

variable "kms_deletion_window_days" {
  description = "KMS key deletion window in days"
  type        = number
  default     = 30
}

##############################################
# Delivery Status Logging
##############################################

variable "enable_delivery_status" {
  description = "Enable delivery status logging to CloudWatch"
  type        = bool
  default     = false
}

variable "http_success_feedback_sample_rate" {
  description = "Sample rate for HTTP success feedback (0-100)"
  type        = number
  default     = 100
  validation {
    condition     = var.http_success_feedback_sample_rate >= 0 && var.http_success_feedback_sample_rate <= 100
    error_message = "Sample rate must be between 0 and 100."
  }
}

variable "lambda_success_feedback_sample_rate" {
  description = "Sample rate for Lambda success feedback (0-100)"
  type        = number
  default     = 100
  validation {
    condition     = var.lambda_success_feedback_sample_rate >= 0 && var.lambda_success_feedback_sample_rate <= 100
    error_message = "Sample rate must be between 0 and 100."
  }
}

variable "sqs_success_feedback_sample_rate" {
  description = "Sample rate for SQS success feedback (0-100)"
  type        = number
  default     = 100
  validation {
    condition     = var.sqs_success_feedback_sample_rate >= 0 && var.sqs_success_feedback_sample_rate <= 100
    error_message = "Sample rate must be between 0 and 100."
  }
}

variable "firehose_success_feedback_sample_rate" {
  description = "Sample rate for Firehose success feedback (0-100)"
  type        = number
  default     = 100
  validation {
    condition     = var.firehose_success_feedback_sample_rate >= 0 && var.firehose_success_feedback_sample_rate <= 100
    error_message = "Sample rate must be between 0 and 100."
  }
}

variable "application_success_feedback_sample_rate" {
  description = "Sample rate for application success feedback (0-100)"
  type        = number
  default     = 100
  validation {
    condition     = var.application_success_feedback_sample_rate >= 0 && var.application_success_feedback_sample_rate <= 100
    error_message = "Sample rate must be between 0 and 100."
  }
}

##############################################
# Topic Policy Configuration
##############################################

variable "topic_policy" {
  description = "Custom topic policy JSON (null = use allowed_publishers)"
  type        = string
  default     = null
}

variable "allowed_publishers" {
  description = "List of AWS principal ARNs allowed to publish"
  type        = list(string)
  default     = []
}

variable "allow_cloudwatch_events" {
  description = "Allow CloudWatch Events/EventBridge to publish"
  type        = bool
  default     = false
}

##############################################
# Subscriptions
##############################################

variable "sqs_subscriptions" {
  description = "List of SQS queue subscriptions"
  type = list(object({
    queue_arn            = string
    raw_message_delivery = optional(bool, false)
    filter_policy        = optional(string, null)
    filter_policy_scope  = optional(string, "MessageAttributes")
    redrive_policy       = optional(string, null)
  }))
  default = []
}

variable "lambda_subscriptions" {
  description = "List of Lambda function subscriptions"
  type = list(object({
    function_arn        = string
    filter_policy       = optional(string, null)
    filter_policy_scope = optional(string, "MessageAttributes")
    redrive_policy      = optional(string, null)
  }))
  default = []
}

variable "http_subscriptions" {
  description = "List of HTTP/HTTPS endpoint subscriptions"
  type = list(object({
    endpoint_url         = string
    use_https            = optional(bool, true)
    raw_message_delivery = optional(bool, false)
    filter_policy        = optional(string, null)
    filter_policy_scope  = optional(string, "MessageAttributes")
    redrive_policy       = optional(string, null)
  }))
  default = []
}

variable "email_subscriptions" {
  description = "List of email addresses for subscriptions"
  type        = list(string)
  default     = []
}

##############################################
# CloudWatch Alarms Configuration
##############################################

variable "enable_cloudwatch_alarms" {
  description = "Enable CloudWatch alarms for the topic"
  type        = bool
  default     = true
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
