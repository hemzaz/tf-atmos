# RDS Secrets Manager Automatic Rotation
# Implements 30-day automatic rotation using AWS Serverless Application Repository Lambda

# Lambda function for secrets rotation (using AWS SAR)
# This uses the official AWS rotation function from the Serverless Application Repository
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# Security group for rotation Lambda function
resource "aws_security_group" "secrets_rotation_lambda" {
  count = var.enable_secrets_rotation ? 1 : 0

  name        = "${var.tags["Environment"]}-${var.identifier}-rotation-lambda-sg"
  description = "Security group for RDS secrets rotation Lambda function"
  vpc_id      = var.vpc_id

  # Outbound to RDS instance
  egress {
    description     = "Database access for rotation"
    from_port       = var.port
    to_port         = var.port
    protocol        = "tcp"
    security_groups = [aws_security_group.rds.id]
  }

  # Outbound to Secrets Manager API
  egress {
    description = "HTTPS for Secrets Manager API"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name    = "${var.tags["Environment"]}-${var.identifier}-rotation-lambda-sg"
      Purpose = "secrets-rotation"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# Allow Lambda to connect to RDS
resource "aws_security_group_rule" "rds_allow_rotation_lambda" {
  count = var.enable_secrets_rotation ? 1 : 0

  type                     = "ingress"
  description              = "Allow secrets rotation Lambda to connect"
  from_port                = var.port
  to_port                  = var.port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.secrets_rotation_lambda[0].id
  security_group_id        = aws_security_group.rds.id
}

# IAM role for rotation Lambda
resource "aws_iam_role" "secrets_rotation" {
  count = var.enable_secrets_rotation ? 1 : 0

  name = "${var.tags["Environment"]}-${var.identifier}-rotation-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name    = "${var.tags["Environment"]}-${var.identifier}-rotation-lambda-role"
      Purpose = "secrets-rotation-lambda"
    }
  )
}

# IAM policy for rotation Lambda
resource "aws_iam_role_policy" "secrets_rotation" {
  count = var.enable_secrets_rotation ? 1 : 0

  name = "${var.tags["Environment"]}-${var.identifier}-rotation-lambda-policy"
  role = aws_iam_role.secrets_rotation[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:DescribeSecret",
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue",
          "secretsmanager:UpdateSecretVersionStage"
        ]
        Resource = aws_secretsmanager_secret.db_password.arn
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetRandomPassword"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.tags["Environment"]}-${var.identifier}-rotation:*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface",
          "ec2:AssignPrivateIpAddresses",
          "ec2:UnassignPrivateIpAddresses"
        ]
        Resource = "*"
      }
    ]
  })
}

# Lambda function for rotation (inline code approach)
resource "aws_lambda_function" "secrets_rotation" {
  count = var.enable_secrets_rotation ? 1 : 0

  filename         = data.archive_file.rotation_lambda[0].output_path
  function_name    = "${var.tags["Environment"]}-${var.identifier}-rotation"
  role            = aws_iam_role.secrets_rotation[0].arn
  handler         = "index.handler"
  runtime         = "python3.11"
  timeout         = 300
  source_code_hash = data.archive_file.rotation_lambda[0].output_base64sha256

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = [aws_security_group.secrets_rotation_lambda[0].id]
  }

  environment {
    variables = {
      SECRETS_MANAGER_ENDPOINT = "https://secretsmanager.${data.aws_region.current.name}.amazonaws.com"
    }
  }

  tags = merge(
    var.tags,
    {
      Name    = "${var.tags["Environment"]}-${var.identifier}-rotation"
      Purpose = "rds-secret-rotation"
    }
  )

  depends_on = [
    aws_iam_role_policy.secrets_rotation
  ]
}

# Create Lambda deployment package
data "archive_file" "rotation_lambda" {
  count = var.enable_secrets_rotation ? 1 : 0

  type        = "zip"
  output_path = "${path.module}/rotation-lambda.zip"

  source {
    content  = file("${path.module}/lambda/rotation.py")
    filename = "index.py"
  }
}

# Lambda permission for Secrets Manager to invoke
resource "aws_lambda_permission" "secrets_rotation" {
  count = var.enable_secrets_rotation ? 1 : 0

  statement_id  = "AllowExecutionFromSecretsManager"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.secrets_rotation[0].function_name
  principal     = "secretsmanager.amazonaws.com"
}

# CloudWatch Log Group for rotation Lambda
resource "aws_cloudwatch_log_group" "rotation_lambda" {
  count = var.enable_secrets_rotation ? 1 : 0

  name              = "/aws/lambda/${aws_lambda_function.secrets_rotation[0].function_name}"
  retention_in_days = var.rotation_logs_retention_days

  tags = merge(
    var.tags,
    {
      Name    = "${var.tags["Environment"]}-${var.identifier}-rotation-logs"
      Purpose = "rotation-lambda-logs"
    }
  )
}

# Enable automatic rotation on the secret
resource "aws_secretsmanager_secret_rotation" "db_password" {
  count = var.enable_secrets_rotation ? 1 : 0

  secret_id           = aws_secretsmanager_secret.db_password.id
  rotation_lambda_arn = aws_lambda_function.secrets_rotation[0].arn

  rotation_rules {
    automatically_after_days = var.rotation_days
  }

  depends_on = [
    aws_lambda_permission.secrets_rotation
  ]
}

# CloudWatch Alarm for rotation failures
resource "aws_cloudwatch_metric_alarm" "rotation_failed" {
  count = var.enable_secrets_rotation && var.enable_rotation_alarms ? 1 : 0

  alarm_name          = "${var.tags["Environment"]}-${var.identifier}-rotation-failed"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "Alert when RDS secret rotation fails"
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.rotation_alarm_actions

  dimensions = {
    FunctionName = aws_lambda_function.secrets_rotation[0].function_name
  }

  tags = var.tags
}

# CloudWatch Alarm for rotation duration
resource "aws_cloudwatch_metric_alarm" "rotation_duration" {
  count = var.enable_secrets_rotation && var.enable_rotation_alarms ? 1 : 0

  alarm_name          = "${var.tags["Environment"]}-${var.identifier}-rotation-duration-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Maximum"
  threshold           = var.rotation_duration_alarm_threshold
  alarm_description   = "Alert when RDS secret rotation takes too long"
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.rotation_alarm_actions

  dimensions = {
    FunctionName = aws_lambda_function.secrets_rotation[0].function_name
  }

  tags = var.tags
}

# SNS topic for rotation notifications (optional)
resource "aws_sns_topic" "rotation_notifications" {
  count = var.enable_secrets_rotation && var.create_rotation_sns_topic ? 1 : 0

  name              = "${var.tags["Environment"]}-${var.identifier}-rotation-notifications"
  kms_master_key_id = var.sns_kms_key_id

  tags = merge(
    var.tags,
    {
      Name    = "${var.tags["Environment"]}-${var.identifier}-rotation-notifications"
      Purpose = "rotation-notifications"
    }
  )
}

# SNS topic subscription (email example)
resource "aws_sns_topic_subscription" "rotation_notifications_email" {
  count = var.enable_secrets_rotation && var.create_rotation_sns_topic && length(var.rotation_notification_emails) > 0 ? length(var.rotation_notification_emails) : 0

  topic_arn = aws_sns_topic.rotation_notifications[0].arn
  protocol  = "email"
  endpoint  = var.rotation_notification_emails[count.index]
}

# EventBridge rule for successful rotations
resource "aws_cloudwatch_event_rule" "rotation_success" {
  count = var.enable_secrets_rotation && var.enable_rotation_events ? 1 : 0

  name        = "${var.tags["Environment"]}-${var.identifier}-rotation-success"
  description = "Capture successful RDS secret rotations"

  event_pattern = jsonencode({
    source      = ["aws.secretsmanager"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["secretsmanager.amazonaws.com"]
      eventName   = ["RotateSecret"]
      requestParameters = {
        secretId = [aws_secretsmanager_secret.db_password.arn]
      }
      responseElements = {
        versionId = [{ exists = true }]
      }
    }
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "rotation_success" {
  count = var.enable_secrets_rotation && var.enable_rotation_events && var.create_rotation_sns_topic ? 1 : 0

  rule      = aws_cloudwatch_event_rule.rotation_success[0].name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.rotation_notifications[0].arn
}

# SNS topic policy for EventBridge
resource "aws_sns_topic_policy" "rotation_notifications" {
  count = var.enable_secrets_rotation && var.create_rotation_sns_topic ? 1 : 0

  arn = aws_sns_topic.rotation_notifications[0].arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.rotation_notifications[0].arn
      }
    ]
  })
}
