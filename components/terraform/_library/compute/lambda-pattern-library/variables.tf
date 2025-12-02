# Lambda Pattern Library Module - Variables
# Version: 1.0.0

# ==============================================================================
# NAMING AND TAGGING
# ==============================================================================

variable "name_prefix" {
  description = "Name prefix for all resources"
  type        = string

  validation {
    condition     = length(var.name_prefix) > 0 && length(var.name_prefix) <= 32
    error_message = "Name prefix must be between 1 and 32 characters."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, production)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "production", "test", "qa"], var.environment)
    error_message = "Environment must be one of: dev, staging, production, test, qa."
  }
}

variable "function_name" {
  description = "Name of the Lambda function"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.function_name))
    error_message = "Function name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# ==============================================================================
# DEPLOYMENT PATTERN
# ==============================================================================

variable "deployment_pattern" {
  description = "Deployment pattern: rest-api, event-driven, stream-processing, scheduled, vpc-integrated"
  type        = string
  default     = "event-driven"

  validation {
    condition = contains([
      "rest-api",
      "event-driven",
      "stream-processing",
      "scheduled",
      "vpc-integrated"
    ], var.deployment_pattern)
    error_message = "Deployment pattern must be one of: rest-api, event-driven, stream-processing, scheduled, vpc-integrated."
  }
}

# ==============================================================================
# FUNCTION CONFIGURATION
# ==============================================================================

variable "runtime" {
  description = "Lambda runtime (e.g., python3.11, nodejs20.x, java17, go1.x)"
  type        = string

  validation {
    condition = can(regex("^(python3\\.(8|9|10|11|12)|nodejs(18|20)\\.x|java(11|17|21)|go1\\.x|dotnet(6|7|8)|ruby3\\.2|provided\\.al2|provided\\.al2023)$", var.runtime))
    error_message = "Runtime must be a valid AWS Lambda runtime identifier."
  }
}

variable "handler" {
  description = "Lambda function handler"
  type        = string
  default     = "index.handler"
}

variable "source_code_path" {
  description = "Path to the function source code (directory or zip file)"
  type        = string
}

variable "source_code_hash" {
  description = "Hash of the source code for detecting changes (optional)"
  type        = string
  default     = null
}

variable "memory_size" {
  description = "Amount of memory in MB your Lambda Function can use at runtime"
  type        = number
  default     = 128

  validation {
    condition     = var.memory_size >= 128 && var.memory_size <= 10240
    error_message = "Memory size must be between 128 and 10240 MB."
  }
}

variable "timeout" {
  description = "Amount of time your Lambda Function has to run in seconds"
  type        = number
  default     = 3

  validation {
    condition     = var.timeout >= 1 && var.timeout <= 900
    error_message = "Timeout must be between 1 and 900 seconds (15 minutes)."
  }
}

variable "reserved_concurrent_executions" {
  description = "Amount of reserved concurrent executions for this function (0 to disable, -1 for unreserved)"
  type        = number
  default     = -1

  validation {
    condition     = var.reserved_concurrent_executions >= -1
    error_message = "Reserved concurrent executions must be -1 (unreserved) or a positive number."
  }
}

variable "architectures" {
  description = "Instruction set architecture for Lambda function (x86_64 or arm64)"
  type        = list(string)
  default     = ["x86_64"]

  validation {
    condition = alltrue([
      for arch in var.architectures : contains(["x86_64", "arm64"], arch)
    ])
    error_message = "Architecture must be either x86_64 or arm64."
  }
}

# ==============================================================================
# ENVIRONMENT VARIABLES AND SECRETS
# ==============================================================================

variable "environment_variables" {
  description = "Map of environment variables for the Lambda function"
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = "Map of secret names to ARNs (Secrets Manager or SSM Parameter Store)"
  type        = map(string)
  default     = {}
}

variable "kms_key_arn" {
  description = "KMS key ARN for encrypting environment variables"
  type        = string
  default     = null
}

# ==============================================================================
# VPC CONFIGURATION
# ==============================================================================

variable "enable_vpc" {
  description = "Enable VPC configuration for Lambda function"
  type        = bool
  default     = false
}

variable "vpc_subnet_ids" {
  description = "List of subnet IDs for VPC configuration"
  type        = list(string)
  default     = []
}

variable "vpc_security_group_ids" {
  description = "List of security group IDs for VPC configuration"
  type        = list(string)
  default     = []
}

# ==============================================================================
# LAYERS
# ==============================================================================

variable "layers" {
  description = "List of Lambda Layer ARNs to attach to the function"
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.layers) <= 5
    error_message = "A Lambda function can have at most 5 layers."
  }
}

# ==============================================================================
# PROVISIONED CONCURRENCY
# ==============================================================================

variable "enable_provisioned_concurrency" {
  description = "Enable provisioned concurrency for the function"
  type        = bool
  default     = false
}

variable "provisioned_concurrent_executions" {
  description = "Number of provisioned concurrent executions"
  type        = number
  default     = 1

  validation {
    condition     = var.provisioned_concurrent_executions >= 1
    error_message = "Provisioned concurrent executions must be at least 1."
  }
}

# ==============================================================================
# DEAD LETTER QUEUE
# ==============================================================================

variable "enable_dlq" {
  description = "Enable Dead Letter Queue for failed invocations"
  type        = bool
  default     = true
}

variable "dlq_target_arn" {
  description = "ARN of SQS queue or SNS topic for DLQ (leave empty to create SQS queue)"
  type        = string
  default     = null
}

# ==============================================================================
# TRACING AND MONITORING
# ==============================================================================

variable "enable_xray_tracing" {
  description = "Enable AWS X-Ray tracing"
  type        = bool
  default     = true
}

variable "tracing_mode" {
  description = "X-Ray tracing mode (Active or PassThrough)"
  type        = string
  default     = "Active"

  validation {
    condition     = contains(["Active", "PassThrough"], var.tracing_mode)
    error_message = "Tracing mode must be either Active or PassThrough."
  }
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 7

  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180,
      365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention must be a valid CloudWatch Logs retention period."
  }
}

# ==============================================================================
# API GATEWAY CONFIGURATION (REST API PATTERN)
# ==============================================================================

variable "enable_api_gateway" {
  description = "Enable API Gateway REST API integration"
  type        = bool
  default     = false
}

variable "api_gateway_type" {
  description = "Type of API Gateway (REST or HTTP)"
  type        = string
  default     = "REST"

  validation {
    condition     = contains(["REST", "HTTP"], var.api_gateway_type)
    error_message = "API Gateway type must be either REST or HTTP."
  }
}

variable "api_gateway_stage_name" {
  description = "Name of the API Gateway stage"
  type        = string
  default     = "prod"
}

variable "api_gateway_throttle_burst_limit" {
  description = "API Gateway throttle burst limit"
  type        = number
  default     = 5000
}

variable "api_gateway_throttle_rate_limit" {
  description = "API Gateway throttle rate limit (requests per second)"
  type        = number
  default     = 10000
}

variable "enable_api_gateway_access_logs" {
  description = "Enable access logs for API Gateway"
  type        = bool
  default     = true
}

variable "api_gateway_authorization" {
  description = "Authorization type for API Gateway (NONE, AWS_IAM, COGNITO_USER_POOLS, CUSTOM)"
  type        = string
  default     = "NONE"

  validation {
    condition     = contains(["NONE", "AWS_IAM", "COGNITO_USER_POOLS", "CUSTOM"], var.api_gateway_authorization)
    error_message = "Authorization must be one of: NONE, AWS_IAM, COGNITO_USER_POOLS, CUSTOM."
  }
}

variable "api_gateway_authorizer_id" {
  description = "ID of the API Gateway authorizer (required if authorization is not NONE)"
  type        = string
  default     = null
}

variable "api_gateway_cors_enabled" {
  description = "Enable CORS for API Gateway"
  type        = bool
  default     = true
}

variable "api_gateway_cors_allow_origins" {
  description = "Allowed origins for CORS"
  type        = list(string)
  default     = ["*"]
}

# ==============================================================================
# EVENTBRIDGE CONFIGURATION (EVENT-DRIVEN PATTERN)
# ==============================================================================

variable "enable_eventbridge" {
  description = "Enable EventBridge rule integration"
  type        = bool
  default     = false
}

variable "eventbridge_rules" {
  description = "List of EventBridge rules to create"
  type = list(object({
    name                = string
    description         = optional(string)
    schedule_expression = optional(string)
    event_pattern       = optional(string)
    enabled             = optional(bool, true)
  }))
  default = []
}

variable "eventbridge_bus_name" {
  description = "Name of the EventBridge bus (default or custom)"
  type        = string
  default     = "default"
}

# ==============================================================================
# SQS CONFIGURATION (QUEUE PROCESSING PATTERN)
# ==============================================================================

variable "enable_sqs_trigger" {
  description = "Enable SQS queue as Lambda trigger"
  type        = bool
  default     = false
}

variable "sqs_queue_arn" {
  description = "ARN of SQS queue to use as trigger (leave empty to create new queue)"
  type        = string
  default     = null
}

variable "sqs_batch_size" {
  description = "Maximum number of messages to retrieve in a single batch"
  type        = number
  default     = 10

  validation {
    condition     = var.sqs_batch_size >= 1 && var.sqs_batch_size <= 10000
    error_message = "Batch size must be between 1 and 10000."
  }
}

variable "sqs_maximum_batching_window_in_seconds" {
  description = "Maximum amount of time to gather records before invoking the function"
  type        = number
  default     = 0

  validation {
    condition     = var.sqs_maximum_batching_window_in_seconds >= 0 && var.sqs_maximum_batching_window_in_seconds <= 300
    error_message = "Maximum batching window must be between 0 and 300 seconds."
  }
}

variable "create_sqs_queue" {
  description = "Create a new SQS queue for the Lambda function"
  type        = bool
  default     = false
}

variable "sqs_message_retention_seconds" {
  description = "Message retention period for SQS queue (if creating new queue)"
  type        = number
  default     = 345600

  validation {
    condition     = var.sqs_message_retention_seconds >= 60 && var.sqs_message_retention_seconds <= 1209600
    error_message = "Message retention must be between 60 seconds and 14 days."
  }
}

# ==============================================================================
# SNS CONFIGURATION
# ==============================================================================

variable "enable_sns_trigger" {
  description = "Enable SNS topic as Lambda trigger"
  type        = bool
  default     = false
}

variable "sns_topic_arn" {
  description = "ARN of SNS topic to use as trigger"
  type        = string
  default     = null
}

# ==============================================================================
# KINESIS/DynamoDB STREAMS (STREAM PROCESSING PATTERN)
# ==============================================================================

variable "enable_stream_trigger" {
  description = "Enable Kinesis or DynamoDB stream as Lambda trigger"
  type        = bool
  default     = false
}

variable "stream_arn" {
  description = "ARN of Kinesis stream or DynamoDB stream"
  type        = string
  default     = null
}

variable "stream_batch_size" {
  description = "Maximum number of records to retrieve in a single batch from stream"
  type        = number
  default     = 100

  validation {
    condition     = var.stream_batch_size >= 1 && var.stream_batch_size <= 10000
    error_message = "Stream batch size must be between 1 and 10000."
  }
}

variable "stream_starting_position" {
  description = "Position in stream where Lambda starts reading (TRIM_HORIZON, LATEST, AT_TIMESTAMP)"
  type        = string
  default     = "LATEST"

  validation {
    condition     = contains(["TRIM_HORIZON", "LATEST", "AT_TIMESTAMP"], var.stream_starting_position)
    error_message = "Starting position must be TRIM_HORIZON, LATEST, or AT_TIMESTAMP."
  }
}

variable "stream_parallelization_factor" {
  description = "Number of concurrent batches per shard"
  type        = number
  default     = 1

  validation {
    condition     = var.stream_parallelization_factor >= 1 && var.stream_parallelization_factor <= 10
    error_message = "Parallelization factor must be between 1 and 10."
  }
}

variable "stream_maximum_retry_attempts" {
  description = "Maximum number of retry attempts for failed records"
  type        = number
  default     = 3

  validation {
    condition     = var.stream_maximum_retry_attempts >= -1 && var.stream_maximum_retry_attempts <= 10000
    error_message = "Maximum retry attempts must be between -1 (infinite) and 10000."
  }
}

# ==============================================================================
# FUNCTION URL (PUBLIC HTTPS ENDPOINT)
# ==============================================================================

variable "enable_function_url" {
  description = "Enable Lambda Function URL (public HTTPS endpoint)"
  type        = bool
  default     = false
}

variable "function_url_auth_type" {
  description = "Authorization type for function URL (NONE or AWS_IAM)"
  type        = string
  default     = "AWS_IAM"

  validation {
    condition     = contains(["NONE", "AWS_IAM"], var.function_url_auth_type)
    error_message = "Function URL auth type must be either NONE or AWS_IAM."
  }
}

variable "function_url_cors" {
  description = "CORS configuration for function URL"
  type = object({
    allow_credentials = optional(bool, false)
    allow_headers     = optional(list(string), ["*"])
    allow_methods     = optional(list(string), ["*"])
    allow_origins     = optional(list(string), ["*"])
    expose_headers    = optional(list(string), [])
    max_age           = optional(number, 0)
  })
  default = null
}

# ==============================================================================
# IAM ROLE CONFIGURATION
# ==============================================================================

variable "create_role" {
  description = "Create IAM role for Lambda function"
  type        = bool
  default     = true
}

variable "role_arn" {
  description = "ARN of existing IAM role to use (if create_role is false)"
  type        = string
  default     = null
}

variable "role_policies" {
  description = "List of IAM policy ARNs to attach to the Lambda role"
  type        = list(string)
  default     = []
}

variable "inline_policies" {
  description = "Map of inline policy names to policy documents"
  type        = map(string)
  default     = {}
}

# ==============================================================================
# FILE SYSTEM (EFS)
# ==============================================================================

variable "enable_efs" {
  description = "Enable EFS file system mount"
  type        = bool
  default     = false
}

variable "efs_access_point_arn" {
  description = "ARN of EFS access point"
  type        = string
  default     = null
}

variable "efs_local_mount_path" {
  description = "Local mount path for EFS in Lambda (/mnt/...)"
  type        = string
  default     = "/mnt/efs"

  validation {
    condition     = can(regex("^/mnt/[a-zA-Z0-9_-]+$", var.efs_local_mount_path))
    error_message = "EFS mount path must start with /mnt/ and contain only alphanumeric characters, hyphens, and underscores."
  }
}

# ==============================================================================
# CODE SIGNING
# ==============================================================================

variable "enable_code_signing" {
  description = "Enable code signing for Lambda function"
  type        = bool
  default     = false
}

variable "code_signing_config_arn" {
  description = "ARN of code signing configuration"
  type        = string
  default     = null
}

# ==============================================================================
# COST OPTIMIZATION
# ==============================================================================

variable "enable_snapstart" {
  description = "Enable SnapStart for faster cold starts (Java 11+ and Kotlin)"
  type        = bool
  default     = false
}
