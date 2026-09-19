# Lambda Function Resource Template
# Production-ready Lambda function with a least-privilege execution role,
# log group, optional VPC access, event source permissions and alarms.
#
# Usage: copy this file into its own module directory (for example
# components/terraform/<component>/modules/lambda-function/main.tf) and call it
# with a `module` block. It is self-contained: the module declares its own
# provider requirements and takes no provider configuration.

terraform {
  required_version = ">= 1.16.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
  }
}

locals {
  function_name = "${var.name_prefix}-${var.function_name}"
  vpc_enabled   = length(var.vpc_subnet_ids) > 0
}

data "aws_partition" "current" {}

# Lambda function
resource "aws_lambda_function" "this" {
  function_name = local.function_name
  role          = aws_iam_role.lambda_execution.arn

  # Code configuration (exactly one of filename, s3_bucket/s3_key or image_uri)
  filename         = var.filename
  source_code_hash = var.filename != null ? filebase64sha256(var.filename) : null

  s3_bucket         = var.s3_bucket
  s3_key            = var.s3_key
  s3_object_version = var.s3_object_version

  image_uri    = var.image_uri
  package_type = var.package_type

  # Runtime configuration
  runtime     = var.package_type == "Zip" ? var.runtime : null
  handler     = var.package_type == "Zip" ? var.handler : null
  timeout     = var.timeout
  memory_size = var.memory_size

  architectures = var.architectures
  layers        = var.layers
  publish       = var.provisioned_concurrent_executions != null

  reserved_concurrent_executions = var.reserved_concurrent_executions

  dynamic "environment" {
    for_each = length(var.environment_variables) > 0 ? [var.environment_variables] : []
    content {
      variables = environment.value
    }
  }

  dynamic "vpc_config" {
    for_each = local.vpc_enabled ? [1] : []
    content {
      subnet_ids         = var.vpc_subnet_ids
      security_group_ids = var.vpc_security_group_ids
    }
  }

  dynamic "dead_letter_config" {
    for_each = var.dead_letter_target_arn != null ? [var.dead_letter_target_arn] : []
    content {
      target_arn = dead_letter_config.value
    }
  }

  tracing_config {
    mode = var.tracing_mode
  }

  dynamic "image_config" {
    for_each = var.package_type == "Image" ? [1] : []
    content {
      command           = var.image_command
      entry_point       = var.image_entry_point
      working_directory = var.image_working_directory
    }
  }

  logging_config {
    log_format = "JSON"
    log_group  = aws_cloudwatch_log_group.lambda_logs.name
  }

  tags = var.tags

  depends_on = [
    aws_iam_role_policy.lambda_logging,
    aws_cloudwatch_log_group.lambda_logs,
  ]
}

# Provisioned concurrency targets the published version
resource "aws_lambda_provisioned_concurrency_config" "this" {
  count = var.provisioned_concurrent_executions != null ? 1 : 0

  function_name                     = aws_lambda_function.this.function_name
  qualifier                         = aws_lambda_function.this.version
  provisioned_concurrent_executions = var.provisioned_concurrent_executions
}

# Lambda execution role
data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_execution" {
  name               = "${local.function_name}-execution-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  tags = var.tags
}

# CloudWatch Logs permissions, scoped to this function's log group
data "aws_iam_policy_document" "lambda_logging" {
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["${aws_cloudwatch_log_group.lambda_logs.arn}:*"]
  }
}

resource "aws_iam_role_policy" "lambda_logging" {
  name   = "${local.function_name}-logging"
  role   = aws_iam_role.lambda_execution.id
  policy = data.aws_iam_policy_document.lambda_logging.json
}

# VPC execution policy (if VPC is configured)
resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  count = local.vpc_enabled ? 1 : 0

  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# X-Ray tracing policy
resource "aws_iam_role_policy_attachment" "lambda_xray" {
  count = var.tracing_mode == "Active" ? 1 : 0

  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

# Custom inline policy (pass an aws_iam_policy_document JSON)
resource "aws_iam_role_policy" "lambda_custom" {
  count = var.custom_policy_json != null ? 1 : 0

  name   = "${local.function_name}-custom-policy"
  role   = aws_iam_role.lambda_execution.id
  policy = var.custom_policy_json
}

# Additional managed policies
resource "aws_iam_role_policy_attachment" "lambda_managed_policies" {
  for_each = toset(var.managed_policy_arns)

  role       = aws_iam_role.lambda_execution.name
  policy_arn = each.value
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.log_kms_key_arn

  tags = var.tags
}

# Lambda permissions for API Gateway
resource "aws_lambda_permission" "api_gateway" {
  count = var.api_gateway_source_arn != null ? 1 : 0

  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = var.api_gateway_source_arn
}

# Lambda permissions for S3 (key = logical name of the bucket)
resource "aws_lambda_permission" "s3" {
  for_each = var.s3_bucket_notifications

  statement_id  = "AllowExecutionFromS3-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = each.value.bucket_arn
}

# Lambda permissions for EventBridge (key = logical name of the rule)
resource "aws_lambda_permission" "eventbridge" {
  for_each = var.eventbridge_rules

  statement_id  = "AllowExecutionFromEventBridge-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.function_name
  principal     = "events.amazonaws.com"
  source_arn    = each.value.rule_arn
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  count = var.enable_error_alarm ? 1 : 0

  alarm_name          = "${local.function_name}-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = var.error_alarm_threshold
  alarm_description   = "Lambda function errors for ${local.function_name}"
  alarm_actions       = var.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.this.function_name
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  count = var.enable_duration_alarm ? 1 : 0

  alarm_name          = "${local.function_name}-duration"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Average"
  threshold           = var.duration_alarm_threshold
  alarm_description   = "Lambda function duration for ${local.function_name}"
  alarm_actions       = var.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.this.function_name
  }

  tags = var.tags
}

# Variables
variable "name_prefix" {
  type        = string
  description = "Name prefix for resources (e.g. <tenant>-<account>-<environment>)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.name_prefix))
    error_message = "The name_prefix must contain only letters, numbers, hyphens and underscores."
  }
}

variable "function_name" {
  type        = string
  description = "Name of the Lambda function (appended to name_prefix)"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.function_name))
    error_message = "The function_name must contain only letters, numbers, hyphens and underscores."
  }
}

# Code source variables
variable "filename" {
  type        = string
  description = "Path to the function's deployment package"
  default     = null
}

variable "s3_bucket" {
  type        = string
  description = "S3 bucket containing the function's deployment package"
  default     = null
}

variable "s3_key" {
  type        = string
  description = "S3 key of the function's deployment package"
  default     = null
}

variable "s3_object_version" {
  type        = string
  description = "Object version of the function's deployment package"
  default     = null
}

variable "image_uri" {
  type        = string
  description = "ECR image URI containing the function's deployment package"
  default     = null
}

variable "package_type" {
  type        = string
  description = "Lambda deployment package type"
  default     = "Zip"

  validation {
    condition     = contains(["Zip", "Image"], var.package_type)
    error_message = "Package type must be either 'Zip' or 'Image'."
  }
}

# Runtime configuration
variable "runtime" {
  type        = string
  description = "Runtime environment for the Lambda function (Zip packages only)"
  default     = "python3.13"
}

variable "handler" {
  type        = string
  description = "Function entrypoint (Zip packages only)"
  default     = "lambda_function.lambda_handler"
}

variable "timeout" {
  type        = number
  description = "Function timeout in seconds"
  default     = 30

  validation {
    condition     = var.timeout >= 1 && var.timeout <= 900
    error_message = "Timeout must be between 1 and 900 seconds."
  }
}

variable "memory_size" {
  type        = number
  description = "Amount of memory available to the function in MB"
  default     = 128

  validation {
    condition     = var.memory_size >= 128 && var.memory_size <= 10240
    error_message = "Memory size must be between 128 MB and 10,240 MB."
  }
}

variable "architectures" {
  type        = list(string)
  description = "Instruction set architecture for the function"
  default     = ["arm64"]

  validation {
    condition     = alltrue([for arch in var.architectures : contains(["x86_64", "arm64"], arch)])
    error_message = "Architectures must be 'x86_64' or 'arm64'."
  }
}

variable "environment_variables" {
  type        = map(string)
  description = "Environment variables for the function (never put secrets here; read them from Secrets Manager at runtime)"
  default     = {}
}

variable "vpc_subnet_ids" {
  type        = list(string)
  description = "VPC subnet IDs (empty to run outside a VPC)"
  default     = []
}

variable "vpc_security_group_ids" {
  type        = list(string)
  description = "VPC security group IDs (required when vpc_subnet_ids is set)"
  default     = []
}

variable "dead_letter_target_arn" {
  type        = string
  description = "ARN of the SQS queue or SNS topic used as dead letter target"
  default     = null
}

variable "tracing_mode" {
  type        = string
  description = "X-Ray tracing mode"
  default     = "PassThrough"

  validation {
    condition     = contains(["Active", "PassThrough"], var.tracing_mode)
    error_message = "Tracing mode must be either 'Active' or 'PassThrough'."
  }
}

variable "layers" {
  type        = list(string)
  description = "List of Lambda Layer ARNs"
  default     = []
}

variable "reserved_concurrent_executions" {
  type        = number
  description = "Reserved concurrent executions (-1 for unreserved)"
  default     = -1
}

variable "provisioned_concurrent_executions" {
  type        = number
  description = "Provisioned concurrent executions on the published version (null to disable)"
  default     = null

  validation {
    condition     = var.provisioned_concurrent_executions == null || try(var.provisioned_concurrent_executions >= 1, false)
    error_message = "Provisioned concurrent executions must be at least 1 when set."
  }
}

# Image configuration (for container images)
variable "image_command" {
  type        = list(string)
  description = "Container image command"
  default     = null
}

variable "image_entry_point" {
  type        = list(string)
  description = "Container image entry point"
  default     = null
}

variable "image_working_directory" {
  type        = string
  description = "Container image working directory"
  default     = null
}

# IAM configuration
variable "custom_policy_json" {
  type        = string
  description = "Custom inline IAM policy JSON for the execution role (null for none)"
  default     = null
}

variable "managed_policy_arns" {
  type        = list(string)
  description = "List of managed policy ARNs to attach to the execution role"
  default     = []
}

# Monitoring configuration
variable "log_retention_days" {
  type        = number
  description = "CloudWatch log retention in days"
  default     = 14

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "Log retention must be a valid CloudWatch retention period."
  }
}

variable "log_kms_key_arn" {
  type        = string
  description = "KMS key ARN used to encrypt the log group (null for AWS-managed encryption)"
  default     = null
}

variable "enable_error_alarm" {
  type        = bool
  description = "Enable error count alarm"
  default     = true
}

variable "error_alarm_threshold" {
  type        = number
  description = "Error count threshold for alarm"
  default     = 5
}

variable "enable_duration_alarm" {
  type        = bool
  description = "Enable duration alarm"
  default     = true
}

variable "duration_alarm_threshold" {
  type        = number
  description = "Duration threshold for alarm (ms)"
  default     = 10000
}

variable "alarm_actions" {
  type        = list(string)
  description = "ARNs (e.g. SNS topics) notified when an alarm fires"
  default     = []
}

# Event sources
variable "api_gateway_source_arn" {
  type        = string
  description = "API Gateway execution ARN allowed to invoke the function"
  default     = null
}

variable "s3_bucket_notifications" {
  type = map(object({
    bucket_arn = string
  }))
  description = "S3 buckets allowed to invoke the function, keyed by a logical name"
  default     = {}
}

variable "eventbridge_rules" {
  type = map(object({
    rule_arn = string
  }))
  description = "EventBridge rules allowed to invoke the function, keyed by a logical name"
  default     = {}
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to resources"
  default     = {}
}

# Outputs
output "function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.this.function_name
}

output "function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.this.arn
}

output "function_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.this.invoke_arn
}

output "function_version" {
  description = "Version of the Lambda function"
  value       = aws_lambda_function.this.version
}

output "execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution.arn
}

output "log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}
