# Lambda Pattern Library Module - Main Configuration
# Version: 1.0.0
# Supports: REST API, Event-Driven, Stream Processing, Scheduled, VPC-Integrated patterns

locals {
  function_name = "${var.name_prefix}-${var.function_name}"

  common_tags = merge(
    var.tags,
    {
      Name             = local.function_name
      Environment      = var.environment
      ManagedBy        = "terraform"
      Module           = "lambda-pattern-library"
      DeploymentPattern = var.deployment_pattern
    }
  )

  # Merge environment variables with secrets
  environment_variables = merge(
    var.environment_variables,
    {
      ENVIRONMENT = var.environment
      FUNCTION_NAME = local.function_name
    }
  )
}

# ==============================================================================
# IAM ROLE FOR LAMBDA
# ==============================================================================

resource "aws_iam_role" "lambda" {
  count = var.create_role ? 1 : 0

  name = "${local.function_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

# Basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  count = var.create_role ? 1 : 0

  role       = aws_iam_role.lambda[0].name
  policy_arn = var.enable_vpc ? "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole" : "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# X-Ray tracing policy
resource "aws_iam_role_policy_attachment" "lambda_xray" {
  count = var.create_role && var.enable_xray_tracing ? 1 : 0

  role       = aws_iam_role.lambda[0].name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

# Custom policy attachments
resource "aws_iam_role_policy_attachment" "lambda_custom" {
  for_each = var.create_role ? toset(var.role_policies) : []

  role       = aws_iam_role.lambda[0].name
  policy_arn = each.value
}

# Inline policies
resource "aws_iam_role_policy" "lambda_inline" {
  for_each = var.create_role ? var.inline_policies : {}

  name   = each.key
  role   = aws_iam_role.lambda[0].id
  policy = each.value
}

# Secrets Manager access policy
resource "aws_iam_role_policy" "secrets" {
  count = var.create_role && length(var.secrets) > 0 ? 1 : 0

  name = "${local.function_name}-secrets"
  role = aws_iam_role.lambda[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",
        "ssm:GetParameter",
        "ssm:GetParameters",
        "kms:Decrypt"
      ]
      Resource = values(var.secrets)
    }]
  })
}

# ==============================================================================
# CLOUDWATCH LOG GROUP
# ==============================================================================

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

# ==============================================================================
# DEAD LETTER QUEUE
# ==============================================================================

resource "aws_sqs_queue" "dlq" {
  count = var.enable_dlq && var.dlq_target_arn == null ? 1 : 0

  name                       = "${local.function_name}-dlq"
  message_retention_seconds  = 1209600  # 14 days
  visibility_timeout_seconds = 300

  tags = local.common_tags
}

# ==============================================================================
# SQS QUEUE (FOR SQS PATTERN)
# ==============================================================================

resource "aws_sqs_queue" "trigger" {
  count = var.create_sqs_queue ? 1 : 0

  name                       = "${local.function_name}-queue"
  message_retention_seconds  = var.sqs_message_retention_seconds
  visibility_timeout_seconds = var.timeout * 6  # 6x Lambda timeout

  tags = local.common_tags
}

resource "aws_sqs_queue" "trigger_dlq" {
  count = var.create_sqs_queue ? 1 : 0

  name                       = "${local.function_name}-queue-dlq"
  message_retention_seconds  = 1209600

  tags = local.common_tags
}

resource "aws_sqs_queue_redrive_policy" "trigger" {
  count = var.create_sqs_queue ? 1 : 0

  queue_url = aws_sqs_queue.trigger[0].url
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.trigger_dlq[0].arn
    maxReceiveCount     = 3
  })
}

# ==============================================================================
# LAMBDA FUNCTION
# ==============================================================================

data "archive_file" "lambda" {
  count = can(regex("\\.zip$", var.source_code_path)) ? 0 : 1

  type        = "zip"
  source_dir  = var.source_code_path
  output_path = "${path.module}/.terraform/${local.function_name}.zip"
}

resource "aws_lambda_function" "main" {
  function_name = local.function_name
  description   = "Lambda function for ${var.deployment_pattern} pattern"
  role          = var.create_role ? aws_iam_role.lambda[0].arn : var.role_arn

  filename         = can(regex("\\.zip$", var.source_code_path)) ? var.source_code_path : data.archive_file.lambda[0].output_path
  source_code_hash = var.source_code_hash != null ? var.source_code_hash : (can(regex("\\.zip$", var.source_code_path)) ? filebase64sha256(var.source_code_path) : data.archive_file.lambda[0].output_base64sha256)

  handler       = var.handler
  runtime       = var.runtime
  architectures = var.architectures
  timeout       = var.timeout
  memory_size   = var.memory_size

  reserved_concurrent_executions = var.reserved_concurrent_executions

  layers = var.layers

  dynamic "environment" {
    for_each = length(local.environment_variables) > 0 ? [1] : []
    content {
      variables = local.environment_variables
    }
  }

  kms_key_arn = var.kms_key_arn

  dynamic "vpc_config" {
    for_each = var.enable_vpc ? [1] : []
    content {
      subnet_ids         = var.vpc_subnet_ids
      security_group_ids = var.vpc_security_group_ids
    }
  }

  dynamic "dead_letter_config" {
    for_each = var.enable_dlq ? [1] : []
    content {
      target_arn = var.dlq_target_arn != null ? var.dlq_target_arn : aws_sqs_queue.dlq[0].arn
    }
  }

  dynamic "file_system_config" {
    for_each = var.enable_efs ? [1] : []
    content {
      arn              = var.efs_access_point_arn
      local_mount_path = var.efs_local_mount_path
    }
  }

  tracing_config {
    mode = var.enable_xray_tracing ? var.tracing_mode : "PassThrough"
  }

  dynamic "snap_start" {
    for_each = var.enable_snapstart ? [1] : []
    content {
      apply_on = "PublishedVersions"
    }
  }

  code_signing_config_arn = var.enable_code_signing ? var.code_signing_config_arn : null

  tags = local.common_tags

  depends_on = [
    aws_cloudwatch_log_group.lambda,
    aws_iam_role_policy_attachment.lambda_basic
  ]
}

# ==============================================================================
# LAMBDA ALIAS
# ==============================================================================

resource "aws_lambda_alias" "main" {
  name             = var.environment
  function_name    = aws_lambda_function.main.function_name
  function_version = aws_lambda_function.main.version

  lifecycle {
    ignore_changes = [function_version]
  }
}

# ==============================================================================
# PROVISIONED CONCURRENCY
# ==============================================================================

resource "aws_lambda_provisioned_concurrency_config" "main" {
  count = var.enable_provisioned_concurrency ? 1 : 0

  function_name                     = aws_lambda_function.main.function_name
  provisioned_concurrent_executions = var.provisioned_concurrent_executions
  qualifier                         = aws_lambda_alias.main.name
}

# ==============================================================================
# FUNCTION URL
# ==============================================================================

resource "aws_lambda_function_url" "main" {
  count = var.enable_function_url ? 1 : 0

  function_name      = aws_lambda_function.main.function_name
  authorization_type = var.function_url_auth_type

  dynamic "cors" {
    for_each = var.function_url_cors != null ? [var.function_url_cors] : []
    content {
      allow_credentials = cors.value.allow_credentials
      allow_headers     = cors.value.allow_headers
      allow_methods     = cors.value.allow_methods
      allow_origins     = cors.value.allow_origins
      expose_headers    = cors.value.expose_headers
      max_age           = cors.value.max_age
    }
  }
}

# ==============================================================================
# API GATEWAY REST API (REST API PATTERN)
# ==============================================================================

module "api_gateway" {
  source = "./modules/api-gateway-lambda"
  count  = var.enable_api_gateway ? 1 : 0

  name_prefix            = var.name_prefix
  function_name          = var.function_name
  lambda_function_arn    = aws_lambda_function.main.arn
  lambda_function_name   = aws_lambda_function.main.function_name
  stage_name             = var.api_gateway_stage_name
  api_type               = var.api_gateway_type
  throttle_burst_limit   = var.api_gateway_throttle_burst_limit
  throttle_rate_limit    = var.api_gateway_throttle_rate_limit
  enable_access_logs     = var.enable_api_gateway_access_logs
  authorization          = var.api_gateway_authorization
  authorizer_id          = var.api_gateway_authorizer_id
  cors_enabled           = var.api_gateway_cors_enabled
  cors_allow_origins     = var.api_gateway_cors_allow_origins

  tags = local.common_tags
}

# ==============================================================================
# EVENTBRIDGE RULES (EVENT-DRIVEN PATTERN)
# ==============================================================================

module "eventbridge" {
  source = "./modules/eventbridge-lambda"
  count  = var.enable_eventbridge ? 1 : 0

  name_prefix         = var.name_prefix
  function_name       = var.function_name
  lambda_function_arn = aws_lambda_function.main.arn
  event_bus_name      = var.eventbridge_bus_name
  rules               = var.eventbridge_rules

  tags = local.common_tags
}

# ==============================================================================
# SQS TRIGGER (QUEUE PROCESSING PATTERN)
# ==============================================================================

module "sqs_trigger" {
  source = "./modules/sqs-lambda"
  count  = var.enable_sqs_trigger ? 1 : 0

  lambda_function_arn                    = aws_lambda_function.main.arn
  lambda_function_name                   = aws_lambda_function.main.function_name
  sqs_queue_arn                          = var.sqs_queue_arn != null ? var.sqs_queue_arn : aws_sqs_queue.trigger[0].arn
  batch_size                             = var.sqs_batch_size
  maximum_batching_window_in_seconds    = var.sqs_maximum_batching_window_in_seconds
}

# ==============================================================================
# SNS TRIGGER
# ==============================================================================

resource "aws_lambda_permission" "sns" {
  count = var.enable_sns_trigger && var.sns_topic_arn != null ? 1 : 0

  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.main.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = var.sns_topic_arn
}

resource "aws_sns_topic_subscription" "lambda" {
  count = var.enable_sns_trigger && var.sns_topic_arn != null ? 1 : 0

  topic_arn = var.sns_topic_arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.main.arn
}

# ==============================================================================
# STREAM TRIGGER (KINESIS/DYNAMODB STREAMS)
# ==============================================================================

resource "aws_lambda_event_source_mapping" "stream" {
  count = var.enable_stream_trigger && var.stream_arn != null ? 1 : 0

  event_source_arn                   = var.stream_arn
  function_name                      = aws_lambda_function.main.arn
  starting_position                  = var.stream_starting_position
  batch_size                         = var.stream_batch_size
  parallelization_factor             = var.stream_parallelization_factor
  maximum_retry_attempts             = var.stream_maximum_retry_attempts
  bisect_batch_on_function_error     = true
  maximum_record_age_in_seconds      = 86400  # 24 hours

  destination_config {
    on_failure {
      destination_arn = var.enable_dlq ? (var.dlq_target_arn != null ? var.dlq_target_arn : aws_sqs_queue.dlq[0].arn) : null
    }
  }
}

# IAM policy for stream access
resource "aws_iam_role_policy" "stream" {
  count = var.create_role && var.enable_stream_trigger && var.stream_arn != null ? 1 : 0

  name = "${local.function_name}-stream"
  role = aws_iam_role.lambda[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "kinesis:GetRecords",
        "kinesis:GetShardIterator",
        "kinesis:DescribeStream",
        "kinesis:ListShards",
        "dynamodb:GetRecords",
        "dynamodb:GetShardIterator",
        "dynamodb:DescribeStream",
        "dynamodb:ListStreams"
      ]
      Resource = var.stream_arn
    }]
  })
}
