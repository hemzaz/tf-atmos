variable "name_prefix" {
  type        = string
  description = "Prefix for resource names"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.name_prefix))
    error_message = "Name prefix must contain only alphanumeric characters and hyphens."
  }
}

variable "environment" {
  type        = string
  description = "Environment name (production, staging, development)"
  default     = "production"

  validation {
    condition     = contains(["production", "staging", "development"], var.environment)
    error_message = "Environment must be production, staging, or development."
  }
}

# Sampling Rules
variable "create_default_sampling_rule" {
  type        = bool
  description = "Create default sampling rule"
  default     = true
}

variable "default_reservoir_size" {
  type        = number
  description = "Default reservoir size (traces per second)"
  default     = 1

  validation {
    condition     = var.default_reservoir_size >= 0 && var.default_reservoir_size <= 100
    error_message = "Reservoir size must be between 0 and 100."
  }
}

variable "default_fixed_rate" {
  type        = number
  description = "Default fixed sampling rate (0.0 to 1.0)"
  default     = 0.05

  validation {
    condition     = var.default_fixed_rate >= 0.0 && var.default_fixed_rate <= 1.0
    error_message = "Fixed rate must be between 0.0 and 1.0."
  }
}

variable "enable_high_value_sampling" {
  type        = bool
  description = "Enable high-value path sampling (100% rate)"
  default     = true
}

variable "high_value_url_pattern" {
  type        = string
  description = "URL pattern for high-value sampling"
  default     = "/api/*/critical/*"
}

variable "custom_sampling_rules" {
  type = map(object({
    priority       = number
    reservoir_size = number
    fixed_rate     = number
    url_path       = optional(string)
    host           = optional(string)
    http_method    = optional(string)
    service_type   = optional(string)
    service_name   = optional(string)
    resource_arn   = optional(string)
  }))
  description = "Custom sampling rules"
  default     = {}
}

# X-Ray Groups
variable "create_default_group" {
  type        = bool
  description = "Create default X-Ray group"
  default     = true
}

variable "default_group_filter" {
  type        = string
  description = "Filter expression for default group"
  default     = "service(\"*\")"
}

variable "create_error_group" {
  type        = bool
  description = "Create error tracking group"
  default     = true
}

variable "create_slow_requests_group" {
  type        = bool
  description = "Create slow request tracking group"
  default     = true
}

variable "slow_request_threshold" {
  type        = number
  description = "Threshold in seconds for slow requests"
  default     = 3

  validation {
    condition     = var.slow_request_threshold > 0
    error_message = "Slow request threshold must be greater than 0."
  }
}

variable "custom_groups" {
  type = map(object({
    filter_expression = string
  }))
  description = "Custom X-Ray groups"
  default     = {}
}

# Insights
variable "enable_insights" {
  type        = bool
  description = "Enable X-Ray Insights"
  default     = true
}

variable "enable_insights_notifications" {
  type        = bool
  description = "Enable notifications for X-Ray Insights"
  default     = true
}

# Lambda Integration
variable "enable_lambda_integration" {
  type        = bool
  description = "Enable Lambda function X-Ray integration"
  default     = false
}

variable "lambda_function_names" {
  type        = list(string)
  description = "Lambda function names to enable X-Ray"
  default     = []
}

variable "lambda_success_destination" {
  type        = string
  description = "ARN of success destination for Lambda"
  default     = ""
}

variable "lambda_failure_destination" {
  type        = string
  description = "ARN of failure destination for Lambda"
  default     = ""
}

# API Gateway Integration
variable "enable_api_gateway_integration" {
  type        = bool
  description = "Enable API Gateway X-Ray integration"
  default     = false
}

variable "api_gateway_names" {
  type        = list(string)
  description = "API Gateway names to enable X-Ray"
  default     = []
}

variable "api_gateway_stage_name" {
  type        = string
  description = "API Gateway stage name"
  default     = "prod"
}

# Cost Optimization
variable "enable_cost_optimization" {
  type        = bool
  description = "Enable cost-optimized sampling strategies"
  default     = true
}

# Alarms
variable "create_trace_alarms" {
  type        = bool
  description = "Create CloudWatch alarms for traces"
  default     = true
}

variable "error_rate_threshold" {
  type        = number
  description = "Error rate threshold for alarms (percentage)"
  default     = 5

  validation {
    condition     = var.error_rate_threshold >= 0 && var.error_rate_threshold <= 100
    error_message = "Error rate threshold must be between 0 and 100."
  }
}

variable "alarm_actions" {
  type        = list(string)
  description = "SNS topic ARNs for alarm notifications"
  default     = []
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to resources"
  default     = {}
}
