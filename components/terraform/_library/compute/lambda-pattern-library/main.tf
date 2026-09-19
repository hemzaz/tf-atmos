# Lambda Pattern Library Module - Main Configuration
# Version: 1.0.0
# Supports: REST API, Event-Driven, Stream Processing, Scheduled, VPC-Integrated patterns

locals {
  function_name = "${var.name_prefix}-${var.function_name}"

  common_tags = merge(
    var.tags,
    {
      Name              = local.function_name
      Environment       = var.environment
      ManagedBy         = "terraform"
      Module            = "lambda-pattern-library"
      DeploymentPattern = var.deployment_pattern
    }
  )

  # Merge environment variables with secrets
  environment_variables = merge(
    var.environment_variables,
    {
      ENVIRONMENT   = var.environment
      FUNCTION_NAME = local.function_name
    }
  )

  dlq_arn = var.enable_dlq ? (var.dlq_target_arn != null ? var.dlq_target_arn : aws_sqs_queue.dlq[0].arn) : null

  sqs_trigger_queue_arn = var.sqs_queue_arn != null ? var.sqs_queue_arn : one(aws_sqs_queue.trigger[*].arn)

  source_is_zip = can(regex("\\.zip$", var.source_code_path))
}

# ==============================================================================
# IAM ROLE FOR LAMBDA
# ==============================================================================

data "aws_partition" "current" {}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  count = var.create_role ? 1 : 0

  name = "${local.function_name}-role"

  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = local.common_tags
}

# Basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  count = var.create_role ? 1 : 0

  role       = aws_iam_role.lambda[0].name
  policy_arn = var.enable_vpc ? "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole" : "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# X-Ray tracing policy
resource "aws_iam_role_policy_attachment" "lambda_xray" {
  count = var.create_role && var.enable_xray_tracing ? 1 : 0

  role       = aws_iam_role.lambda[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AWSXRayDaemonWriteAccess"
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
data "aws_iam_policy_document" "secrets" {
  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "ssm:GetParameter",
      "ssm:GetParameters",
      "kms:Decrypt"
    ]
    resources = values(var.secrets)
  }
}

resource "aws_iam_role_policy" "secrets" {
  count = var.create_role && length(var.secrets) > 0 ? 1 : 0

  name = "${local.function_name}-secrets"
  role = aws_iam_role.lambda[0].id

  policy = data.aws_iam_policy_document.secrets.json
}

# The execution role must be able to deliver failed async invocations / stream
# records to the dead letter target (SQS or SNS).
data "aws_iam_policy_document" "dlq" {
  statement {
    effect    = "Allow"
    actions   = ["sqs:SendMessage", "sns:Publish"]
    resources = compact([local.dlq_arn])
  }
}

resource "aws_iam_role_policy" "dlq" {
  count = var.create_role && var.enable_dlq ? 1 : 0

  name   = "${local.function_name}-dlq"
  role   = aws_iam_role.lambda[0].id
  policy = data.aws_iam_policy_document.dlq.json
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
  message_retention_seconds  = 1209600 # 14 days
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
  visibility_timeout_seconds = var.timeout * 6 # 6x Lambda timeout

  tags = local.common_tags
}

resource "aws_sqs_queue" "trigger_dlq" {
  count = var.create_sqs_queue ? 1 : 0

  name                      = "${local.function_name}-queue-dlq"
  message_retention_seconds = 1209600

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
  count = local.source_is_zip ? 0 : 1

  type        = "zip"
  source_dir  = var.source_code_path
  output_path = "${path.module}/.terraform/${local.function_name}.zip"
}

resource "aws_lambda_function" "main" {
  function_name = local.function_name
  description   = "Lambda function for ${var.deployment_pattern} pattern"
  role          = var.create_role ? aws_iam_role.lambda[0].arn : var.role_arn

  filename         = local.source_is_zip ? var.source_code_path : data.archive_file.lambda[0].output_path
  source_code_hash = var.source_code_hash != null ? var.source_code_hash : (local.source_is_zip ? filebase64sha256(var.source_code_path) : data.archive_file.lambda[0].output_base64sha256)

  # Provisioned concurrency and SnapStart both require a published version.
  publish = var.enable_provisioned_concurrency || var.enable_snapstart

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
      target_arn = local.dlq_arn
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
    aws_iam_role_policy_attachment.lambda_basic,
    aws_iam_role_policy.dlq
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

# API Gateway (REST API pattern) resources live in api_gateway.tf.

# ==============================================================================
# EVENTBRIDGE RULES (EVENT-DRIVEN PATTERN)
# ==============================================================================

# Implemented inline (previously referenced a non-existent ./modules/eventbridge-lambda).
resource "aws_cloudwatch_event_rule" "lambda" {
  for_each = var.enable_eventbridge ? { for rule in var.eventbridge_rules : rule.name => rule } : {}

  name                = "${local.function_name}-${each.key}"
  description         = each.value.description
  event_bus_name      = var.eventbridge_bus_name
  schedule_expression = each.value.schedule_expression
  event_pattern       = each.value.event_pattern
  state               = each.value.enabled ? "ENABLED" : "DISABLED"

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "lambda" {
  for_each = aws_cloudwatch_event_rule.lambda

  rule           = each.value.name
  event_bus_name = each.value.event_bus_name
  target_id      = "lambda"
  arn            = aws_lambda_function.main.arn
}

resource "aws_lambda_permission" "eventbridge" {
  for_each = aws_cloudwatch_event_rule.lambda

  statement_id  = "AllowExecutionFromEventBridge-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.main.function_name
  principal     = "events.amazonaws.com"
  source_arn    = each.value.arn
}

# ==============================================================================
# SQS TRIGGER (QUEUE PROCESSING PATTERN)
# ==============================================================================

# Implemented inline (previously referenced a non-existent ./modules/sqs-lambda).
resource "aws_lambda_event_source_mapping" "sqs" {
  count = var.enable_sqs_trigger ? 1 : 0

  event_source_arn                   = local.sqs_trigger_queue_arn
  function_name                      = aws_lambda_function.main.arn
  batch_size                         = var.sqs_batch_size
  maximum_batching_window_in_seconds = var.sqs_maximum_batching_window_in_seconds

  lifecycle {
    precondition {
      condition     = var.sqs_queue_arn != null || var.create_sqs_queue
      error_message = "enable_sqs_trigger requires sqs_queue_arn or create_sqs_queue = true."
    }
  }

  depends_on = [aws_iam_role_policy.sqs]
}

data "aws_iam_policy_document" "sqs" {
  statement {
    effect = "Allow"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:ChangeMessageVisibility"
    ]
    resources = compact([local.sqs_trigger_queue_arn])
  }
}

resource "aws_iam_role_policy" "sqs" {
  count = var.create_role && var.enable_sqs_trigger ? 1 : 0

  name   = "${local.function_name}-sqs"
  role   = aws_iam_role.lambda[0].id
  policy = data.aws_iam_policy_document.sqs.json
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

  event_source_arn               = var.stream_arn
  function_name                  = aws_lambda_function.main.arn
  starting_position              = var.stream_starting_position
  batch_size                     = var.stream_batch_size
  parallelization_factor         = var.stream_parallelization_factor
  maximum_retry_attempts         = var.stream_maximum_retry_attempts
  bisect_batch_on_function_error = true
  maximum_record_age_in_seconds  = 86400 # 24 hours

  dynamic "destination_config" {
    for_each = local.dlq_arn != null ? [1] : []
    content {
      on_failure {
        destination_arn = local.dlq_arn
      }
    }
  }

  depends_on = [aws_iam_role_policy.stream]
}

# IAM policy for stream access
data "aws_iam_policy_document" "stream" {
  statement {
    effect = "Allow"
    actions = [
      "kinesis:GetRecords",
      "kinesis:GetShardIterator",
      "kinesis:DescribeStream",
      "kinesis:DescribeStreamSummary",
      "kinesis:ListShards",
      "dynamodb:GetRecords",
      "dynamodb:GetShardIterator",
      "dynamodb:DescribeStream",
      "dynamodb:ListStreams"
    ]
    resources = compact([var.stream_arn])
  }
}

resource "aws_iam_role_policy" "stream" {
  count = var.create_role && var.enable_stream_trigger && var.stream_arn != null ? 1 : 0

  name = "${local.function_name}-stream"
  role = aws_iam_role.lambda[0].id

  policy = data.aws_iam_policy_document.stream.json
}
