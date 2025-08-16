# Lambda Function Resource Template
# Production-ready Lambda function with monitoring and security

locals {
  function_name = "${var.name_prefix}-${var.function_name}"
}

# Lambda function
resource "aws_lambda_function" "this" {
  function_name = local.function_name
  role         = aws_iam_role.lambda_execution.arn
  
  # Code configuration
  filename         = var.filename
  source_code_hash = var.filename != null ? filebase64sha256(var.filename) : null
  
  s3_bucket         = var.s3_bucket
  s3_key           = var.s3_key
  s3_object_version = var.s3_object_version
  
  image_uri    = var.image_uri
  package_type = var.package_type
  
  # Runtime configuration
  runtime     = var.package_type == "Zip" ? var.runtime : null
  handler     = var.package_type == "Zip" ? var.handler : null
  timeout     = var.timeout
  memory_size = var.memory_size
  
  # Architecture
  architectures = var.architectures
  
  # Environment variables
  dynamic "environment" {
    for_each = length(var.environment_variables) > 0 ? [1] : []
    content {
      variables = var.environment_variables
    }
  }
  
  # VPC configuration
  dynamic "vpc_config" {
    for_each = var.vpc_subnet_ids != null ? [1] : []
    content {
      subnet_ids         = var.vpc_subnet_ids
      security_group_ids = var.vpc_security_group_ids
    }
  }
  
  # Dead letter queue
  dynamic "dead_letter_config" {
    for_each = var.dead_letter_target_arn != null ? [1] : []
    content {
      target_arn = var.dead_letter_target_arn
    }
  }
  
  # Tracing
  tracing_config {
    mode = var.tracing_mode
  }
  
  # Image configuration for container images
  dynamic "image_config" {
    for_each = var.package_type == "Image" ? [1] : []
    content {
      command           = var.image_command
      entry_point      = var.image_entry_point
      working_directory = var.image_working_directory
    }
  }
  
  # Layers
  layers = var.layers
  
  # Reserved concurrency
  reserved_concurrent_executions = var.reserved_concurrent_executions
  
  # Provisioned concurrency
  dynamic "provisioned_concurrency_config" {
    for_each = var.provisioned_concurrent_executions != null ? [1] : []
    content {
      provisioned_concurrent_executions = var.provisioned_concurrent_executions
    }
  }
  
  tags = var.tags
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_logs,
    aws_cloudwatch_log_group.lambda_logs,
  ]
}

# Lambda execution role
resource "aws_iam_role" "lambda_execution" {
  name = "${local.function_name}-execution-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
  
  tags = var.tags
}

# Basic execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# VPC execution policy (if VPC is configured)
resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  count = var.vpc_subnet_ids != null ? 1 : 0
  
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# X-Ray tracing policy
resource "aws_iam_role_policy_attachment" "lambda_xray" {
  count = var.tracing_mode == "Active" ? 1 : 0
  
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

# CloudWatch Logs permissions
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = aws_iam_policy.lambda_logging.arn
}

resource "aws_iam_policy" "lambda_logging" {
  name = "${local.function_name}-logging"
  path = "/"
  description = "IAM policy for logging from Lambda"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Custom IAM policies
resource "aws_iam_role_policy" "lambda_custom" {
  count = var.custom_policy_json != "" ? 1 : 0
  
  name = "${local.function_name}-custom-policy"
  role = aws_iam_role.lambda_execution.id
  policy = var.custom_policy_json
}

# Attach additional managed policies
resource "aws_iam_role_policy_attachment" "lambda_managed_policies" {
  count = length(var.managed_policy_arns)
  
  role       = aws_iam_role.lambda_execution.name
  policy_arn = var.managed_policy_arns[count.index]
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = var.log_retention_days
  
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

# Lambda permissions for S3
resource "aws_lambda_permission" "s3" {
  count = length(var.s3_bucket_notifications)
  
  statement_id  = "AllowExecutionFromS3-${count.index}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = var.s3_bucket_notifications[count.index].bucket_arn
}

# Lambda permissions for EventBridge
resource "aws_lambda_permission" "eventbridge" {
  count = length(var.eventbridge_rules)
  
  statement_id  = "AllowExecutionFromEventBridge-${count.index}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.function_name
  principal     = "events.amazonaws.com"
  source_arn    = var.eventbridge_rules[count.index].rule_arn
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  count = var.enable_error_alarm ? 1 : 0
  
  alarm_name          = "${local.function_name}-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.error_alarm_threshold
  alarm_description   = "This metric monitors Lambda function errors"
  
  dimensions = {
    FunctionName = aws_lambda_function.this.function_name
  }
  
  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  count = var.enable_duration_alarm ? 1 : 0
  
  alarm_name          = "${local.function_name}-duration"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Average"
  threshold           = var.duration_alarm_threshold
  alarm_description   = "This metric monitors Lambda function duration"
  
  dimensions = {
    FunctionName = aws_lambda_function.this.function_name
  }
  
  tags = var.tags
}

# Variables (essential ones, add more as needed)
variable "name_prefix" {
  type        = string
  description = "Name prefix for resources"
}

variable "function_name" {
  type        = string
  description = "Name of the Lambda function"
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
  description = "Runtime environment for the Lambda function"
  default     = "python3.9"
}

variable "handler" {
  type        = string
  description = "Function entrypoint"
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
  description = "Amount of memory available to the function"
  default     = 128
  
  validation {
    condition     = var.memory_size >= 128 && var.memory_size <= 10240
    error_message = "Memory size must be between 128 MB and 10,240 MB."
  }
}

variable "architectures" {
  type        = list(string)
  description = "Instruction set architecture for the function"
  default     = ["x86_64"]
  
  validation {
    condition = alltrue([
      for arch in var.architectures : contains(["x86_64", "arm64"], arch)
    ])
    error_message = "Architectures must be 'x86_64' or 'arm64'."
  }
}

# Additional variables for environment, VPC, etc.
variable "environment_variables" {
  type        = map(string)
  description = "Environment variables for the function"
  default     = {}
}

variable "vpc_subnet_ids" {
  type        = list(string)
  description = "VPC subnet IDs"
  default     = null
}

variable "vpc_security_group_ids" {
  type        = list(string)
  description = "VPC security group IDs"
  default     = []
}

variable "dead_letter_target_arn" {
  type        = string
  description = "ARN of the dead letter queue"
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
  description = "Reserved concurrent executions"
  default     = null
}

variable "provisioned_concurrent_executions" {
  type        = number
  description = "Provisioned concurrent executions"
  default     = null
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
  description = "Custom IAM policy JSON"
  default     = ""
}

variable "managed_policy_arns" {
  type        = list(string)
  description = "List of managed policy ARNs to attach"
  default     = []
}

# Monitoring configuration
variable "log_retention_days" {
  type        = number
  description = "CloudWatch log retention in days"
  default     = 14
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

# Event sources
variable "api_gateway_source_arn" {
  type        = string
  description = "API Gateway source ARN"
  default     = null
}

variable "s3_bucket_notifications" {
  type = list(object({
    bucket_arn = string
  }))
  description = "S3 bucket notification configurations"
  default     = []
}

variable "eventbridge_rules" {
  type = list(object({
    rule_arn = string
  }))
  description = "EventBridge rule configurations"
  default     = []
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