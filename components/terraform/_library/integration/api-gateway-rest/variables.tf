##############################################
# Required Variables
##############################################

variable "name_prefix" {
  description = "Prefix for resource naming"
  type        = string
}

variable "api_name" {
  description = "Name of the REST API"
  type        = string
}

variable "stage_name" {
  description = "Name of the deployment stage"
  type        = string
}

##############################################
# API Configuration
##############################################

variable "api_description" {
  description = "Description of the REST API"
  type        = string
  default     = null
}

variable "endpoint_type" {
  description = "Endpoint type (EDGE, REGIONAL, PRIVATE)"
  type        = string
  default     = "REGIONAL"
  validation {
    condition     = contains(["EDGE", "REGIONAL", "PRIVATE"], var.endpoint_type)
    error_message = "Endpoint type must be EDGE, REGIONAL, or PRIVATE."
  }
}

variable "vpc_endpoint_ids" {
  description = "VPC endpoint IDs for PRIVATE endpoint type"
  type        = list(string)
  default     = []
}

variable "api_policy" {
  description = "IAM policy document for the API"
  type        = string
  default     = null
}

variable "binary_media_types" {
  description = "List of binary media types supported"
  type        = list(string)
  default     = []
}

variable "enable_compression" {
  description = "Enable payload compression"
  type        = bool
  default     = false
}

variable "minimum_compression_size" {
  description = "Minimum response size to compress (bytes)"
  type        = number
  default     = 1024
}

variable "deployment_trigger" {
  description = "Trigger value for redeployment (change to force redeploy)"
  type        = string
  default     = "initial"
}

##############################################
# Stage Configuration
##############################################

variable "stage_variables" {
  description = "Map of stage variables"
  type        = map(string)
  default     = {}
}

variable "enable_xray_tracing" {
  description = "Enable AWS X-Ray tracing"
  type        = bool
  default     = true
}

##############################################
# Logging Configuration
##############################################

variable "enable_access_logging" {
  description = "Enable access logging to CloudWatch"
  type        = bool
  default     = true
}

variable "create_log_role" {
  description = "Create IAM role for CloudWatch logging"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention in days"
  type        = number
  default     = 30
}

variable "access_log_format" {
  description = "Access log format"
  type        = string
  default     = "$context.requestId $context.extendedRequestId $context.identity.sourceIp $context.requestTime $context.httpMethod $context.routeKey $context.status $context.protocol $context.responseLength"
}

variable "logging_level" {
  description = "Logging level (OFF, ERROR, INFO)"
  type        = string
  default     = "INFO"
  validation {
    condition     = contains(["OFF", "ERROR", "INFO"], var.logging_level)
    error_message = "Logging level must be OFF, ERROR, or INFO."
  }
}

variable "enable_data_trace" {
  description = "Enable full request/response data logging"
  type        = bool
  default     = false
}

variable "enable_metrics" {
  description = "Enable CloudWatch metrics"
  type        = bool
  default     = true
}

##############################################
# Caching Configuration
##############################################

variable "enable_cache" {
  description = "Enable API caching"
  type        = bool
  default     = false
}

variable "cache_cluster_size" {
  description = "Cache cluster size (0.5, 1.6, 6.1, 13.5, 28.4, 58.2, 118, 237)"
  type        = string
  default     = "0.5"
}

variable "cache_ttl_seconds" {
  description = "Cache TTL in seconds"
  type        = number
  default     = 300
}

variable "cache_data_encrypted" {
  description = "Encrypt cache data"
  type        = bool
  default     = true
}

variable "require_authorization_for_cache_control" {
  description = "Require authorization for cache control headers"
  type        = bool
  default     = true
}

##############################################
# Throttling Configuration
##############################################

variable "throttling_burst_limit" {
  description = "Throttling burst limit"
  type        = number
  default     = 5000
}

variable "throttling_rate_limit" {
  description = "Throttling rate limit (requests per second)"
  type        = number
  default     = 10000
}

##############################################
# API Keys and Usage Plans
##############################################

variable "api_keys" {
  description = "List of API keys to create"
  type = list(object({
    name        = string
    description = optional(string, null)
    enabled     = optional(bool, true)
    value       = optional(string, null)
  }))
  default = []
}

variable "usage_plans" {
  description = "List of usage plans"
  type = list(object({
    name                 = string
    description          = optional(string, null)
    quota_limit          = optional(number, null)
    quota_offset         = optional(number, 0)
    quota_period         = optional(string, "DAY")
    throttle_burst_limit = optional(number, null)
    throttle_rate_limit  = optional(number, null)
    api_key_names        = optional(list(string), [])
  }))
  default = []
}

##############################################
# WAF Configuration
##############################################

variable "waf_acl_arn" {
  description = "ARN of WAF Web ACL to associate"
  type        = string
  default     = null
}

##############################################
# Custom Domain Configuration
##############################################

variable "custom_domain_name" {
  description = "Custom domain name for the API"
  type        = string
  default     = null
}

variable "certificate_arn" {
  description = "ARN of ACM certificate for custom domain"
  type        = string
  default     = null
}

variable "custom_domain_base_path" {
  description = "Base path mapping for custom domain"
  type        = string
  default     = null
}

variable "custom_domain_security_policy" {
  description = "Security policy for custom domain (TLS_1_0, TLS_1_2)"
  type        = string
  default     = "TLS_1_2"
}

##############################################
# Request Validators
##############################################

variable "request_validators" {
  description = "List of request validators"
  type = list(object({
    name                        = string
    validate_request_body       = optional(bool, false)
    validate_request_parameters = optional(bool, false)
  }))
  default = []
}

##############################################
# CloudWatch Alarms Configuration
##############################################

variable "enable_cloudwatch_alarms" {
  description = "Enable CloudWatch alarms for the API"
  type        = bool
  default     = true
}

variable "alarm_5xx_error_threshold" {
  description = "Threshold for 5XX error alarm"
  type        = number
  default     = 10
}

variable "alarm_latency_threshold" {
  description = "Threshold for latency alarm (milliseconds)"
  type        = number
  default     = 5000
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
