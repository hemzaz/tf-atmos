variable "region" {
  type        = string
  description = "AWS region"
}

variable "log_groups" {
  type = map(object({
    retention_days = number
  }))
  description = "Map of log groups to create"
  default     = {}
}

variable "kms_key_id" {
  type        = string
  description = "KMS key ID for log encryption"
  default     = null
}

variable "create_dashboard" {
  type        = bool
  description = "Whether to create CloudWatch dashboard"
  default     = false
}

variable "vpc_id" {
  type        = string
  description = "VPC ID for dashboard metrics"
  default     = ""
}

variable "rds_instances" {
  type        = list(string)
  description = "List of RDS instances to monitor"
  default     = []
}

variable "ecs_clusters" {
  type        = list(string)
  description = "List of ECS clusters to monitor"
  default     = []
}

variable "lambda_functions" {
  type        = list(string)
  description = "List of Lambda functions to monitor"
  default     = []
}

variable "load_balancers" {
  type        = list(string)
  description = "List of load balancers to monitor"
  default     = []
}

variable "elasticache_clusters" {
  type        = list(string)
  description = "List of ElastiCache clusters to monitor"
  default     = []
}

variable "create_sns_topic" {
  type        = bool
  description = "Whether to create an SNS topic for alarms"
  default     = true
}

variable "alarm_email_subscriptions" {
  type        = list(string)
  description = "List of email addresses to notify for alarms"
  default     = []
}

variable "cpu_alarms" {
  type = map(object({
    namespace          = string
    evaluation_periods = number
    period             = number
    threshold          = number
    dimensions         = map(string)
  }))
  description = "Map of CPU alarms to create"
  default     = {}
}

variable "memory_alarms" {
  type = map(object({
    namespace          = string
    evaluation_periods = number
    period             = number
    threshold          = number
    dimensions         = map(string)
  }))
  description = "Map of memory alarms to create"
  default     = {}
}

variable "db_connection_alarms" {
  type = map(object({
    evaluation_periods = number
    period             = number
    threshold          = number
  }))
  description = "Map of database connection alarms to create"
  default     = {}
}

variable "lambda_error_alarms" {
  type = map(object({
    evaluation_periods = number
    period             = number
    threshold          = number
  }))
  description = "Map of Lambda error alarms to create"
  default     = {}
}

variable "log_metric_filters" {
  type = map(object({
    log_group_name     = string
    pattern            = string
    evaluation_periods = number
    period             = number
    threshold          = number
  }))
  description = "Map of log metric filters to create"
  default     = {}
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to resources"
  default     = {}
}