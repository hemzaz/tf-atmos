variable "region" {
  type        = string
  description = "AWS region"
}

variable "function_name" {
  type        = string
  description = "Name of the Lambda function"
}

variable "handler" {
  type        = string
  description = "Lambda function handler"
}

variable "runtime" {
  type        = string
  description = "Lambda function runtime"
  default     = "nodejs16.x"
}

variable "filename" {
  type        = string
  description = "Path to the Lambda function's deployment package"
  default     = null
}

variable "source_code_hash" {
  type        = string
  description = "Base64-encoded SHA256 hash of the package file"
  default     = null
}

variable "s3_bucket" {
  type        = string
  description = "S3 bucket containing the Lambda function's deployment package"
  default     = null
}

variable "s3_key" {
  type        = string
  description = "S3 key of the Lambda function's deployment package"
  default     = null
}

variable "s3_object_version" {
  type        = string
  description = "S3 object version of the Lambda function's deployment package"
  default     = null
}

variable "layers" {
  type        = list(string)
  description = "List of Lambda layer ARNs to attach"
  default     = []
}

variable "memory_size" {
  type        = number
  description = "Amount of memory in MB for the Lambda function"
  default     = 128
}

variable "timeout" {
  type        = number
  description = "Timeout in seconds for the Lambda function"
  default     = 3
}

variable "publish" {
  type        = bool
  description = "Whether to publish a new Lambda function version"
  default     = false
}

variable "environment_variables" {
  type        = map(string)
  description = "Environment variables for the Lambda function"
  default     = {}
}

variable "kms_key_arn" {
  type        = string
  description = "KMS key ARN for encrypting Lambda environment variables"
  default     = null

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws:kms:", var.kms_key_arn))
    error_message = "KMS key ARN must be a valid AWS KMS key ARN or null."
  }
}

variable "vpc_id" {
  type        = string
  description = "VPC ID for Lambda function"
  default     = null
}

variable "subnet_ids" {
  type        = list(string)
  description = "List of subnet IDs for the Lambda function"
  default     = []
}

variable "dead_letter_target_arn" {
  type        = string
  description = "ARN of the SQS queue or SNS topic for the dead letter target"
  default     = null
}

variable "tracing_mode" {
  type        = string
  description = "X-Ray tracing mode (PassThrough or Active)"
  default     = null
}

variable "log_retention_days" {
  type        = number
  description = "Number of days to retain Lambda logs"
  default     = 7
}

variable "kms_key_id" {
  type        = string
  description = "KMS key ID for log encryption"
  default     = null
}

variable "custom_policy" {
  type        = string
  description = "Custom IAM policy for the Lambda function"
  default     = ""
}

variable "api_gateway_source_arn" {
  type        = string
  description = "ARN of the API Gateway that invokes the Lambda function"
  default     = null
}

variable "s3_source_arn" {
  type        = string
  description = "ARN of the S3 bucket that invokes the Lambda function"
  default     = null
}

variable "cloudwatch_source_arn" {
  type        = string
  description = "ARN of the CloudWatch Events rule that invokes the Lambda function"
  default     = null
}

variable "sns_source_arn" {
  type        = string
  description = "ARN of the SNS topic that invokes the Lambda function"
  default     = null
}

variable "configure_event_invoke" {
  type        = bool
  description = "Whether to configure event invoke settings"
  default     = false
}

variable "maximum_retry_attempts" {
  type        = number
  description = "Maximum number of retry attempts for async invocation"
  default     = 2
}

variable "maximum_event_age_in_seconds" {
  type        = number
  description = "Maximum age of events in seconds"
  default     = 60
}

variable "on_success_destination" {
  type        = string
  description = "ARN of destination resource for successful invocations"
  default     = null
}

variable "on_failure_destination" {
  type        = string
  description = "ARN of destination resource for failed invocations"
  default     = null
}

variable "create_alias" {
  type        = bool
  description = "Whether to create an alias for the Lambda function"
  default     = false
}

variable "alias_name" {
  type        = string
  description = "Name of the Lambda function alias"
  default     = "live"
}

variable "alias_description" {
  type        = string
  description = "Description of the Lambda function alias"
  default     = "Live alias"
}

variable "alias_function_version" {
  type        = string
  description = "Version of the Lambda function to use in the alias"
  default     = "$LATEST"
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to resources"
  default     = {}
}

# Performance Optimization Variables
variable "reserved_concurrent_executions" {
  type        = number
  description = "Amount of reserved concurrent executions for the Lambda function"
  default     = null
  validation {
    condition     = var.reserved_concurrent_executions == null || var.reserved_concurrent_executions >= 0
    error_message = "Reserved concurrent executions must be 0 or greater."
  }
}

variable "provisioned_concurrency_config" {
  type = object({
    provisioned_concurrent_executions = number
    qualifier                         = string
  })
  description = "Provisioned concurrency configuration"
  default     = null
}

variable "routing_config" {
  type = object({
    additional_version_weights = map(number)
  })
  description = "Blue/Green deployment routing configuration"
  default     = null
}

variable "telemetry_log_level" {
  type        = string
  description = "Telemetry log level for Lambda function"
  default     = "WARN"
  validation {
    condition     = contains(["TRACE", "DEBUG", "INFO", "WARN", "ERROR", "FATAL"], var.telemetry_log_level)
    error_message = "Telemetry log level must be one of: TRACE, DEBUG, INFO, WARN, ERROR, FATAL."
  }
}

variable "enable_snapstart" {
  type        = bool
  description = "Enable SnapStart for Java Lambda functions"
  default     = false
}

variable "package_type" {
  type        = string
  description = "Lambda deployment package type (Zip or Image)"
  default     = "Zip"
  validation {
    condition     = contains(["Zip", "Image"], var.package_type)
    error_message = "Package type must be either 'Zip' or 'Image'."
  }
}

variable "architectures" {
  type        = list(string)
  description = "Instruction set architectures supported by the function"
  default     = ["x86_64"]
  validation {
    condition     = alltrue([for arch in var.architectures : contains(["x86_64", "arm64"], arch)])
    error_message = "Architectures must be 'x86_64' and/or 'arm64'."
  }
}

# Container Image Configuration
variable "image_command" {
  type        = list(string)
  description = "Parameters that you want to pass in with entry_point"
  default     = []
}

variable "image_entry_point" {
  type        = list(string)
  description = "Entry point to the application"
  default     = []
}

variable "image_working_directory" {
  type        = string
  description = "Working directory for the Lambda function"
  default     = null
}

# EFS Configuration
variable "efs_access_point_arn" {
  type        = string
  description = "EFS access point ARN for Lambda function"
  default     = null
}

variable "efs_local_mount_path" {
  type        = string
  description = "Local mount path for EFS"
  default     = "/mnt/efs"
}

# Enhanced Security Variables
variable "database_port" {
  type        = number
  description = "Database port for security group egress rule"
  default     = null
}

variable "database_cidr_blocks" {
  type        = list(string)
  description = "CIDR blocks for database access"
  default     = []
}

variable "custom_egress_rules" {
  type = list(object({
    description     = string
    from_port       = number
    to_port         = number
    protocol        = string
    cidr_blocks     = optional(list(string))
    security_groups = optional(list(string))
  }))
  description = "Custom egress rules for Lambda security group"
  default     = []
}

# Performance Monitoring Variables
variable "create_performance_alarms" {
  type        = bool
  description = "Whether to create performance monitoring alarms"
  default     = false
}

variable "duration_alarm_threshold" {
  type        = number
  description = "Duration alarm threshold in milliseconds"
  default     = 30000
}

variable "error_rate_alarm_threshold" {
  type        = number
  description = "Error rate alarm threshold"
  default     = 5
}

variable "throttle_alarm_threshold" {
  type        = number
  description = "Throttle alarm threshold"
  default     = 1
}

variable "sns_topic_arn" {
  type        = string
  description = "SNS topic ARN for alarm notifications"
  default     = null
}

# Scheduling Variables
variable "schedule_expression" {
  type        = string
  description = "CloudWatch Events schedule expression"
  default     = null
}

variable "schedule_enabled" {
  type        = bool
  description = "Whether the schedule is enabled"
  default     = true
}

variable "schedule_input" {
  type        = string
  description = "JSON input for scheduled Lambda invocation"
  default     = null
}

# Network Security Variables
variable "vpc_endpoint_prefix_list_ids" {
  type        = list(string)
  description = "List of VPC endpoint prefix list IDs for AWS services (replaces 0.0.0.0/0)"
  default     = []

  validation {
    condition     = length(var.vpc_endpoint_prefix_list_ids) > 0 || length(var.subnet_ids) == 0
    error_message = "VPC endpoint prefix list IDs are required when deploying Lambda in a VPC. Use data source: data.aws_prefix_list.s3 or create VPC endpoints."
  }
}

variable "allow_http_egress" {
  type        = bool
  description = "Allow HTTP (port 80) egress for package downloads. Not recommended for production."
  default     = false

  validation {
    condition = (
      !var.allow_http_egress ||
      !contains(["prod", "production"], lower(lookup(var.tags, "Environment", "dev")))
    )
    error_message = "HTTP egress is not allowed in production environments. Use HTTPS (port 443) only."
  }
}