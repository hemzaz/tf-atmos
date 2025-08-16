variable "region" {
  type        = string
  description = "AWS region"
}

variable "assume_role_arn" {
  type        = string
  description = "ARN of the IAM role to assume"
  default     = null
}

variable "enabled" {
  type        = bool
  description = "Whether to create the resources. Set to false to avoid creating resources"
  default     = true
}

variable "api_name" {
  type        = string
  description = "Name of the API Gateway"
}

variable "api_type" {
  type        = string
  description = "Type of API Gateway to create - REST or HTTP"
  default     = "REST"
  validation {
    condition     = contains(["REST", "HTTP"], var.api_type)
    error_message = "API type must be either 'REST' or 'HTTP'."
  }
}

variable "description" {
  type        = string
  description = "Description of the API Gateway"
  default     = "API Gateway managed by Terraform"
}

variable "endpoint_type" {
  type        = list(string)
  description = "List of endpoint types for the REST API Gateway, for HTTP API Gateway this is always REGIONAL"
  default     = ["REGIONAL"]
  validation {
    condition     = can([for type in var.endpoint_type : contains(["REGIONAL", "EDGE", "PRIVATE"], type)])
    error_message = "Endpoint type must be one of 'REGIONAL', 'EDGE', or 'PRIVATE'."
  }
}

variable "stage_name" {
  type        = string
  description = "Name of the API Gateway stage"
  default     = "v1"
}

variable "auto_deploy" {
  type        = bool
  description = "Whether to automatically deploy the API (HTTP API only)"
  default     = true
}

variable "domain_name" {
  type        = string
  description = "Custom domain name for the API Gateway"
  default     = null
}

variable "certificate_arn" {
  type        = string
  description = "ARN of the ACM certificate for the custom domain name"
  default     = null
}

variable "base_path" {
  type        = string
  description = "Base path mapping for the custom domain"
  default     = null
}

variable "zone_id" {
  type        = string
  description = "Route53 zone ID for the custom domain name"
  default     = null
}

variable "enable_logging" {
  type        = bool
  description = "Whether to enable CloudWatch logging for the API Gateway"
  default     = true
}

variable "log_format" {
  type        = string
  description = "Log format for CloudWatch logs"
  default     = "{ \"requestId\":\"$context.requestId\", \"ip\": \"$context.identity.sourceIp\", \"requestTime\":\"$context.requestTime\", \"httpMethod\":\"$context.httpMethod\", \"routeKey\":\"$context.routeKey\", \"status\":\"$context.status\", \"protocol\":\"$context.protocol\", \"responseLength\":\"$context.responseLength\", \"integrationError\":\"$context.integrationErrorMessage\" }"
}

variable "log_retention_days" {
  type        = number
  description = "Number of days to retain CloudWatch logs"
  default     = 7
}

variable "kms_key_id" {
  type        = string
  description = "KMS key ID for CloudWatch logs encryption"
  default     = null
}

variable "cors_configuration" {
  type = object({
    allow_origins     = list(string)
    allow_methods     = list(string)
    allow_headers     = list(string)
    expose_headers    = list(string)
    max_age           = number
    allow_credentials = bool
  })
  description = "CORS configuration for the API Gateway"
  default = {
    allow_origins     = ["*"]
    allow_methods     = ["*"]
    allow_headers     = ["*"]
    expose_headers    = []
    max_age           = 3600
    allow_credentials = false
  }
}

variable "minimum_compression_size" {
  type        = number
  description = "Minimum compression size for the REST API"
  default     = -1
}

variable "api_key_source" {
  type        = string
  description = "Source of the API key for REST API requests"
  default     = "HEADER"
  validation {
    condition     = contains(["HEADER", "AUTHORIZER"], var.api_key_source)
    error_message = "API key source must be either 'HEADER' or 'AUTHORIZER'."
  }
}

variable "binary_media_types" {
  type        = list(string)
  description = "List of binary media types supported by the REST API"
  default     = []
}

variable "tracing_enabled" {
  type        = bool
  description = "Whether to enable X-Ray tracing"
  default     = false
}

variable "create_usage_plan" {
  type        = bool
  description = "Whether to create a usage plan for the REST API"
  default     = false
}

variable "usage_plan_quota_limit" {
  type        = number
  description = "Maximum number of requests that can be made in a given time period"
  default     = 1000
}

variable "usage_plan_quota_offset" {
  type        = number
  description = "Number of requests subtracted from the quota limit at the beginning of the period"
  default     = 0
}

variable "usage_plan_quota_period" {
  type        = string
  description = "Time period in which the quota applies"
  default     = "MONTH"
  validation {
    condition     = contains(["DAY", "WEEK", "MONTH"], var.usage_plan_quota_period)
    error_message = "Usage plan quota period must be one of 'DAY', 'WEEK', or 'MONTH'."
  }
}

variable "usage_plan_throttle_burst_limit" {
  type        = number
  description = "Maximum rate at which tokens for usage plans bucket can be used"
  default     = 5
}

variable "usage_plan_throttle_rate_limit" {
  type        = number
  description = "Rate at which tokens for usage plans bucket are added"
  default     = 10
}

variable "create_api_key" {
  type        = bool
  description = "Whether to create an API key for the REST API"
  default     = false
}

variable "authorizer_type" {
  type        = string
  description = "Type of authorizer for the API Gateway"
  default     = null
  validation {
    condition     = var.authorizer_type == null ? true : contains(["COGNITO_USER_POOLS", "TOKEN", "JWT", "REQUEST"], var.authorizer_type)
    error_message = "Authorizer type must be one of 'COGNITO_USER_POOLS', 'TOKEN', 'JWT', or 'REQUEST'."
  }
}

variable "authorizer_identity_source" {
  type        = string
  description = "Source of the identity in an incoming request"
  default     = "method.request.header.Authorization"
}

variable "cognito_user_pool_arns" {
  type        = list(string)
  description = "List of Cognito user pool ARNs for the COGNITO_USER_POOLS authorizer"
  default     = []
}

variable "lambda_authorizer_uri" {
  type        = string
  description = "URI of the Lambda function for the TOKEN or REQUEST authorizer"
  default     = null
}

variable "lambda_authorizer_role_arn" {
  type        = string
  description = "ARN of the IAM role for the Lambda authorizer"
  default     = null
}

variable "jwt_audience" {
  type        = list(string)
  description = "List of allowed audiences for the JWT authorizer"
  default     = []
}

variable "jwt_issuer" {
  type        = string
  description = "Issuer URL for the JWT authorizer"
  default     = null
}

variable "api_resources" {
  type = list(object({
    path_part = string
    parent_id = optional(string)
  }))
  description = "List of resources for the REST API"
  default     = []
}

variable "api_methods" {
  type = list(object({
    resource_id        = string
    http_method        = string
    authorization      = string
    api_key_required   = optional(bool, false)
    request_parameters = optional(map(bool), {})
  }))
  description = "List of methods for the REST API"
  default     = []
}

variable "api_integrations" {
  type = list(object({
    resource_id             = string
    http_method             = string
    integration_http_method = string
    type                    = string
    uri                     = string
    connection_type         = optional(string)
    connection_id           = optional(string)
    timeout_milliseconds    = optional(number, 29000)
    request_parameters      = optional(map(string), {})
    request_templates       = optional(map(string), {})
  }))
  description = "List of integrations for the REST API"
  default     = []
}

variable "create_dashboard" {
  type        = bool
  description = "Whether to create a CloudWatch dashboard for the API Gateway"
  default     = true
}

variable "tags" {
  type        = map(string)
  description = "A map of tags to add to all resources"
  default     = {}
}

# WAF Configuration Variables
variable "enable_waf" {
  type        = bool
  description = "Whether to enable AWS WAF for the API Gateway"
  default     = false
}

variable "waf_rate_limit" {
  type        = number
  description = "The maximum number of requests per 5 minutes from a single IP"
  default     = 10000
  validation {
    condition     = var.waf_rate_limit >= 100 && var.waf_rate_limit <= 2000000000
    error_message = "WAF rate limit must be between 100 and 2,000,000,000."
  }
}

variable "allowed_countries" {
  type        = list(string)
  description = "List of country codes to allow access (empty list disables geo-blocking)"
  default     = []
  validation {
    condition     = alltrue([for country in var.allowed_countries : can(regex("^[A-Z]{2}$", country))])
    error_message = "Country codes must be 2-letter uppercase ISO country codes."
  }
}

# Caching Configuration Variables
variable "enable_caching" {
  type        = bool
  description = "Whether to enable caching for the API Gateway"
  default     = false
}

variable "cache_ttl_seconds" {
  type        = number
  description = "The time to live (TTL) period for cached responses in seconds"
  default     = 300
  validation {
    condition     = var.cache_ttl_seconds >= 0 && var.cache_ttl_seconds <= 3600
    error_message = "Cache TTL must be between 0 and 3600 seconds."
  }
}

variable "cache_key_parameters" {
  type        = list(string)
  description = "List of parameters to include in the cache key"
  default     = []
}

# Throttling Configuration Variables
variable "throttling_rate_limit" {
  type        = number
  description = "The steady-state request rate limit (requests per second)"
  default     = 10000
  validation {
    condition     = var.throttling_rate_limit > 0
    error_message = "Throttling rate limit must be greater than 0."
  }
}

variable "throttling_burst_limit" {
  type        = number
  description = "The burst request rate limit (requests per second)"
  default     = 5000
  validation {
    condition     = var.throttling_burst_limit > 0
    error_message = "Throttling burst limit must be greater than 0."
  }
}

# Logging Configuration Variables
variable "logging_level" {
  type        = string
  description = "The logging level for API Gateway method execution"
  default     = "INFO"
  validation {
    condition     = contains(["OFF", "ERROR", "INFO"], var.logging_level)
    error_message = "Logging level must be one of: OFF, ERROR, INFO."
  }
}

variable "data_trace_enabled" {
  type        = bool
  description = "Whether to enable data trace logging for API Gateway"
  default     = false
}

variable "metrics_enabled" {
  type        = bool
  description = "Whether to enable CloudWatch metrics for API Gateway"
  default     = true
}

# Performance Monitoring Variables
variable "create_performance_alarms" {
  type        = bool
  description = "Whether to create CloudWatch alarms for API performance monitoring"
  default     = false
}

variable "alarm_4xx_threshold" {
  type        = number
  description = "Threshold for 4xx error alarm (number of errors in 5 minutes)"
  default     = 10
}

variable "alarm_5xx_threshold" {
  type        = number
  description = "Threshold for 5xx error alarm (number of errors in 5 minutes)"
  default     = 5
}

variable "alarm_latency_threshold" {
  type        = number
  description = "Threshold for latency alarm in milliseconds"
  default     = 1000
}

variable "sns_topic_arn" {
  type        = string
  description = "SNS topic ARN for sending alarm notifications"
  default     = null
}