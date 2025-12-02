##############################################
# Required Variables
##############################################

variable "name_prefix" {
  description = "Prefix for resource naming"
  type        = string
}

variable "state_machine_name" {
  description = "Name of the Step Functions state machine"
  type        = string
}

variable "definition" {
  description = "Amazon States Language definition of the state machine"
  type        = string
}

##############################################
# State Machine Configuration
##############################################

variable "state_machine_type" {
  description = "Type of state machine (STANDARD or EXPRESS)"
  type        = string
  default     = "STANDARD"
  validation {
    condition     = contains(["STANDARD", "EXPRESS"], var.state_machine_type)
    error_message = "State machine type must be STANDARD or EXPRESS."
  }
}

##############################################
# Logging Configuration
##############################################

variable "enable_logging" {
  description = "Enable CloudWatch Logs for state machine"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention in days"
  type        = number
  default     = 30
}

variable "log_level" {
  description = "Log level (ALL, ERROR, FATAL, OFF)"
  type        = string
  default     = "ERROR"
  validation {
    condition     = contains(["ALL", "ERROR", "FATAL", "OFF"], var.log_level)
    error_message = "Log level must be ALL, ERROR, FATAL, or OFF."
  }
}

variable "log_include_execution_data" {
  description = "Include execution data in logs"
  type        = bool
  default     = false
}

variable "log_kms_key_id" {
  description = "KMS key ID for log encryption"
  type        = string
  default     = null
}

##############################################
# X-Ray Tracing
##############################################

variable "enable_xray_tracing" {
  description = "Enable AWS X-Ray tracing"
  type        = bool
  default     = true
}

##############################################
# IAM Permissions
##############################################

variable "lambda_function_arns" {
  description = "ARNs of Lambda functions to invoke"
  type        = list(string)
  default     = []
}

variable "sqs_queue_arns" {
  description = "ARNs of SQS queues to send messages to"
  type        = list(string)
  default     = []
}

variable "sns_topic_arns" {
  description = "ARNs of SNS topics to publish to"
  type        = list(string)
  default     = []
}

variable "dynamodb_table_arns" {
  description = "ARNs of DynamoDB tables to access"
  type        = list(string)
  default     = []
}

variable "ecs_task_arns" {
  description = "ARNs of ECS tasks to run"
  type        = list(string)
  default     = []
}

variable "ecs_cluster_arns" {
  description = "ARNs of ECS clusters"
  type        = list(string)
  default     = []
}

variable "ecs_task_execution_role_arns" {
  description = "ARNs of ECS task execution roles for PassRole"
  type        = list(string)
  default     = []
}

variable "eventbridge_bus_arns" {
  description = "ARNs of EventBridge buses to put events to"
  type        = list(string)
  default     = []
}

variable "additional_policy_statements" {
  description = "Additional IAM policy statements for the state machine"
  type = list(object({
    sid       = optional(string, null)
    effect    = string
    actions   = list(string)
    resources = list(string)
    conditions = optional(list(object({
      test     = string
      variable = string
      values   = list(string)
    })), [])
  }))
  default = []
}

##############################################
# CloudWatch Alarms Configuration
##############################################

variable "enable_cloudwatch_alarms" {
  description = "Enable CloudWatch alarms for the state machine"
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
