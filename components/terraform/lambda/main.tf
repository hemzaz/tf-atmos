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

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${aws_lambda_function.main.function_name}"
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

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.tags["Environment"]}-${var.function_name}-sg"
    }
  )
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

  dynamic "environment" {
    for_each = length(var.environment_variables) > 0 ? [1] : []
    content {
      variables = var.environment_variables
    }
  }

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

  tags = merge(
    var.tags,
    {
      Name = "${var.tags["Environment"]}-${var.function_name}"
    }
  )
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

resource "aws_lambda_alias" "main" {
  count            = var.create_alias ? 1 : 0
  name             = var.alias_name
  description      = var.alias_description
  function_name    = aws_lambda_function.main.function_name
  function_version = var.alias_function_version
}
