##############################################
# Required Variables
##############################################

variable "name_prefix" {
  description = "Prefix for resource naming"
  type        = string
}

variable "bus_name" {
  description = "Name of the EventBridge event bus"
  type        = string
}

##############################################
# Event Bus Policy
##############################################

variable "event_bus_policy" {
  description = "Custom event bus policy JSON (null = use allowed_accounts)"
  type        = string
  default     = null
}

variable "allowed_accounts" {
  description = "List of AWS account IDs allowed to put events"
  type        = list(string)
  default     = []
}

##############################################
# Event Archive Configuration
##############################################

variable "enable_archive" {
  description = "Enable event archive for replay"
  type        = bool
  default     = false
}

variable "archive_config" {
  description = "Event archive configuration"
  type = object({
    description    = optional(string, null)
    retention_days = optional(number, 0)
    event_pattern  = optional(string, null)
  })
  default = {
    description    = null
    retention_days = 0
    event_pattern  = null
  }
}

##############################################
# Event Rules Configuration
##############################################

variable "event_rules" {
  description = "List of event rules with targets"
  type = list(object({
    name                = string
    description         = optional(string, null)
    event_pattern       = optional(string, null)
    schedule_expression = optional(string, null)
    enabled             = optional(bool, true)
    role_arn            = optional(string, null)
    tags                = optional(map(string), {})

    # Lambda targets
    lambda_targets = optional(list(object({
      function_arn = string
      target_id    = optional(string, null)
      dlq_arn      = optional(string, null)
      input_transformer = optional(object({
        input_paths   = optional(map(string), null)
        input_template = optional(string, null)
      }), null)
      retry_policy = optional(object({
        maximum_event_age      = optional(number, 86400)
        maximum_retry_attempts = optional(number, 2)
      }), null)
    })), [])

    # SQS targets
    sqs_targets = optional(list(object({
      queue_arn        = string
      target_id        = optional(string, null)
      message_group_id = optional(string, null)
      dlq_arn          = optional(string, null)
    })), [])

    # Step Functions targets
    step_functions_targets = optional(list(object({
      state_machine_arn = string
      role_arn          = string
      target_id         = optional(string, null)
      dlq_arn           = optional(string, null)
    })), [])

    # Kinesis targets
    kinesis_targets = optional(list(object({
      stream_arn         = string
      role_arn           = string
      target_id          = optional(string, null)
      partition_key_path = optional(string, null)
    })), [])

    # SNS targets
    sns_targets = optional(list(object({
      topic_arn = string
      target_id = optional(string, null)
      dlq_arn   = optional(string, null)
    })), [])

    # EventBridge Bus targets (cross-bus routing)
    event_bus_targets = optional(list(object({
      event_bus_arn = string
      role_arn      = string
      target_id     = optional(string, null)
    })), [])
  }))
  default = []
}

##############################################
# Schema Registry
##############################################

variable "enable_schema_registry" {
  description = "Enable schema registry for this event bus"
  type        = bool
  default     = false
}

variable "enable_schema_discovery" {
  description = "Enable automatic schema discovery"
  type        = bool
  default     = false
}

##############################################
# CloudWatch Alarms Configuration
##############################################

variable "enable_cloudwatch_alarms" {
  description = "Enable CloudWatch alarms for the event bus"
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
