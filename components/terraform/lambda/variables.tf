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