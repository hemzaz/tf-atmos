# components/terraform/lambda/main.tf
resource "aws_iam_role" "lambda" {
  name = "${var.tags["Environment"]}-${var.function_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })

  tags = merge(
    var.tags,
    {
      Name = "${var.tags["Environment"]}-${var.function_name}-role"
    }
  )
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_vpc_access" {
  count      = length(var.subnet_ids) > 0 ? 1 : 0
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "lambda_custom" {
  count  = var.custom_policy != "" ? 1 : 0
  name   = "${var.tags["Environment"]}-${var.function_name}-custom-policy"
  role   = aws_iam_role.lambda.id
  policy = var.custom_policy
}

# Create log group before the Lambda function to avoid circular dependencies
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.tags["Environment"]}-${var.function_name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_id

  tags = merge(
    var.tags,
    {
      Name = "/aws/lambda/${var.tags["Environment"]}-${var.function_name}"
    }
  )
}

resource "aws_security_group" "lambda" {
  count       = length(var.subnet_ids) > 0 ? 1 : 0
  name        = "${var.tags["Environment"]}-${var.function_name}-sg"
  description = "Security group for ${var.function_name} Lambda function"
  vpc_id      = var.vpc_id

  # More restrictive egress rules for better security
  # Use VPC endpoints instead of 0.0.0.0/0 for AWS services
  egress {
    description     = "HTTPS to AWS services via VPC endpoints"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    prefix_list_ids = var.vpc_endpoint_prefix_list_ids
  }

  # Only allow HTTP if explicitly enabled (not recommended for production)
  dynamic "egress" {
    for_each = var.allow_http_egress ? [1] : []
    content {
      description     = "HTTP for package downloads (only if explicitly enabled)"
      from_port       = 80
      to_port         = 80
      protocol        = "tcp"
      prefix_list_ids = var.vpc_endpoint_prefix_list_ids
    }
  }

  # Database access (if needed)
  dynamic "egress" {
    for_each = var.database_port != null ? [1] : []
    content {
      description = "Database access"
      from_port   = var.database_port
      to_port     = var.database_port
      protocol    = "tcp"
      cidr_blocks = var.database_cidr_blocks
    }
  }

  # Custom egress rules
  dynamic "egress" {
    for_each = var.custom_egress_rules
    content {
      description     = egress.value.description
      from_port       = egress.value.from_port
      to_port         = egress.value.to_port
      protocol        = egress.value.protocol
      cidr_blocks     = lookup(egress.value, "cidr_blocks", null)
      security_groups = lookup(egress.value, "security_groups", null)
    }
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.tags["Environment"]}-${var.function_name}-sg"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lambda_function" "main" {
  function_name     = "${var.tags["Environment"]}-${var.function_name}"
  role              = aws_iam_role.lambda.arn
  handler           = var.handler
  runtime           = var.runtime
  filename          = var.filename
  source_code_hash  = var.source_code_hash
  s3_bucket         = var.s3_bucket
  s3_key            = var.s3_key
  s3_object_version = var.s3_object_version
  layers            = var.layers
  memory_size       = var.memory_size
  timeout           = var.timeout
  publish           = var.publish

  # Performance optimization: reserved concurrency
  reserved_concurrent_executions = var.reserved_concurrent_executions

  # Ensure log group exists before Lambda is created
  depends_on = [aws_cloudwatch_log_group.lambda]

  dynamic "environment" {
    for_each = length(var.environment_variables) > 0 ? [1] : []
    content {
      variables = merge(var.environment_variables, {
        # Add performance optimization environment variables
        _LAMBDA_TELEMETRY_LOG_LEVEL = var.telemetry_log_level
        AWS_LAMBDA_EXEC_WRAPPER     = var.enable_snapstart && contains(["java11", "java17", "java21"], var.runtime) ? "/opt/aws-lambda-snapstart" : null
      })
    }
  }

  # SECURITY: Encrypt environment variables
  kms_key_arn = var.kms_key_arn

  dynamic "vpc_config" {
    for_each = length(var.subnet_ids) > 0 ? [1] : []
    content {
      subnet_ids         = var.subnet_ids
      security_group_ids = [aws_security_group.lambda[0].id]
    }
  }

  dynamic "dead_letter_config" {
    for_each = var.dead_letter_target_arn != null ? [1] : []
    content {
      target_arn = var.dead_letter_target_arn
    }
  }

  dynamic "tracing_config" {
    for_each = var.tracing_mode != null ? [1] : []
    content {
      mode = var.tracing_mode
    }
  }

  # Performance: Provisioned concurrency for predictable performance
  dynamic "snap_start" {
    for_each = var.enable_snapstart && contains(["java11", "java17", "java21"], var.runtime) ? [1] : []
    content {
      apply_on = "PublishedVersions"
    }
  }

  dynamic "file_system_config" {
    for_each = var.efs_access_point_arn != null ? [1] : []
    content {
      arn              = var.efs_access_point_arn
      local_mount_path = var.efs_local_mount_path
    }
  }

  dynamic "image_config" {
    for_each = var.package_type == "Image" ? [1] : []
    content {
      command           = var.image_command
      entry_point       = var.image_entry_point
      working_directory = var.image_working_directory
    }
  }

  package_type = var.package_type
  architectures = var.architectures

  tags = merge(
    var.tags,
    {
      Name = "${var.tags["Environment"]}-${var.function_name}"
    }
  )

  # Add reliability preconditions
  lifecycle {
    # Verify role has been created and has necessary permissions
    precondition {
      condition     = aws_iam_role_policy_attachment.lambda_basic.id != ""
      error_message = "Lambda basic execution role policy must be attached before creating the function."
    }

    # Ensure handler is valid format (function_file.function_name) for non-image packages
    precondition {
      condition     = var.package_type == "Image" || (can(regex("^[a-zA-Z0-9_\\.]+$", var.handler)) && length(split(".", var.handler)) >= 2)
      error_message = "Handler must be in the format 'file_name.function_name' for Zip packages."
    }

    # Memory allocation validation
    precondition {
      condition     = var.memory_size >= 128 && var.memory_size <= 10240
      error_message = "Memory size must be between 128 MB and 10,240 MB."
    }
  }
}

resource "aws_lambda_permission" "api_gateway" {
  count         = var.api_gateway_source_arn != null ? 1 : 0
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.main.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = var.api_gateway_source_arn
}

resource "aws_lambda_permission" "s3" {
  count         = var.s3_source_arn != null ? 1 : 0
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.main.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = var.s3_source_arn
}

resource "aws_lambda_permission" "cloudwatch" {
  count         = var.cloudwatch_source_arn != null ? 1 : 0
  statement_id  = "AllowCloudWatchInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.main.function_name
  principal     = "events.amazonaws.com"
  source_arn    = var.cloudwatch_source_arn
}

resource "aws_lambda_permission" "sns" {
  count         = var.sns_source_arn != null ? 1 : 0
  statement_id  = "AllowSNSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.main.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = var.sns_source_arn
}

resource "aws_lambda_function_event_invoke_config" "main" {
  count                        = var.configure_event_invoke ? 1 : 0
  function_name                = aws_lambda_function.main.function_name
  maximum_retry_attempts       = var.maximum_retry_attempts
  maximum_event_age_in_seconds = var.maximum_event_age_in_seconds

  dynamic "destination_config" {
    for_each = var.on_success_destination != null || var.on_failure_destination != null ? [1] : []
    content {
      dynamic "on_success" {
        for_each = var.on_success_destination != null ? [1] : []
        content {
          destination = var.on_success_destination
        }
      }

      dynamic "on_failure" {
        for_each = var.on_failure_destination != null ? [1] : []
        content {
          destination = var.on_failure_destination
        }
      }
    }
  }
}

# Provisioned Concurrency for consistent performance
resource "aws_lambda_provisioned_concurrency_config" "main" {
  count                             = var.provisioned_concurrency_config != null ? 1 : 0
  function_name                     = aws_lambda_function.main.function_name
  provisioned_concurrent_executions = var.provisioned_concurrency_config.provisioned_concurrent_executions
  qualifier                         = var.provisioned_concurrency_config.qualifier

  depends_on = [aws_lambda_alias.main]
}

# Lambda alias with traffic shifting capabilities
resource "aws_lambda_alias" "main" {
  count            = var.create_alias ? 1 : 0
  name             = var.alias_name
  description      = var.alias_description
  function_name    = aws_lambda_function.main.function_name
  function_version = var.alias_function_version

  # Blue/Green deployment support
  dynamic "routing_config" {
    for_each = var.routing_config != null ? [1] : []
    content {
      additional_version_weights = var.routing_config.additional_version_weights
    }
  }
}

# Enhanced CloudWatch alarms for performance monitoring
resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  count = var.create_performance_alarms ? 1 : 0

  alarm_name          = "${var.tags["Environment"]}-${var.function_name}-high-duration"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Average"
  threshold           = var.duration_alarm_threshold
  alarm_description   = "Lambda function ${var.function_name} duration is too high"
  alarm_actions       = var.sns_topic_arn != null ? [var.sns_topic_arn] : []

  dimensions = {
    FunctionName = aws_lambda_function.main.function_name
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "lambda_error_rate" {
  count = var.create_performance_alarms ? 1 : 0

  alarm_name          = "${var.tags["Environment"]}-${var.function_name}-high-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.error_rate_alarm_threshold
  alarm_description   = "Lambda function ${var.function_name} error rate is too high"
  alarm_actions       = var.sns_topic_arn != null ? [var.sns_topic_arn] : []

  dimensions = {
    FunctionName = aws_lambda_function.main.function_name
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "lambda_throttles" {
  count = var.create_performance_alarms ? 1 : 0

  alarm_name          = "${var.tags["Environment"]}-${var.function_name}-throttles"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Throttles"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.throttle_alarm_threshold
  alarm_description   = "Lambda function ${var.function_name} is being throttled"
  alarm_actions       = var.sns_topic_arn != null ? [var.sns_topic_arn] : []

  dimensions = {
    FunctionName = aws_lambda_function.main.function_name
  }

  tags = var.tags
}

# Cost optimization: Schedule for predictable workloads
resource "aws_cloudwatch_event_rule" "lambda_schedule" {
  count = var.schedule_expression != null ? 1 : 0

  name                = "${var.tags["Environment"]}-${var.function_name}-schedule"
  description         = "Schedule for Lambda function ${var.function_name}"
  schedule_expression = var.schedule_expression
  state               = var.schedule_enabled ? "ENABLED" : "DISABLED"

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "lambda_schedule_target" {
  count = var.schedule_expression != null ? 1 : 0

  rule      = aws_cloudwatch_event_rule.lambda_schedule[0].name
  target_id = "LambdaScheduleTarget"
  arn       = aws_lambda_function.main.arn

  dynamic "input_transformer" {
    for_each = var.schedule_input != null ? [1] : []
    content {
      input_template = var.schedule_input
    }
  }
}

resource "aws_lambda_permission" "allow_eventbridge" {
  count = var.schedule_expression != null ? 1 : 0

  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.main.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.lambda_schedule[0].arn
}
