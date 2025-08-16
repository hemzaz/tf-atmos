# Enhanced DynamoDB table for Terraform state locking
# Optimized for high availability and performance with monitoring

resource "aws_dynamodb_table" "terraform_locks" {
  name         = var.dynamodb_table_name
  billing_mode = var.dynamodb_billing_mode
  hash_key     = "LockID"

  # Provisioned throughput settings (only used if billing_mode is PROVISIONED)
  read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
  write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null

  attribute {
    name = "LockID"
    type = "S"
  }

  # Enable point-in-time recovery for data protection
  point_in_time_recovery {
    enabled = var.enable_point_in_time_recovery
  }

  # Server-side encryption with customer managed KMS key
  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.terraform_state_key.arn
  }

  # Table class optimization for cost savings
  table_class = var.dynamodb_table_class

  # TTL for automatic cleanup of old locks (safety measure)
  ttl {
    attribute_name = "expires_at"
    enabled        = var.enable_lock_ttl
  }

  # Deletion protection for production environments
  deletion_protection_enabled = var.environment == "prod" ? true : var.enable_deletion_protection

  tags = merge(
    var.tags,
    {
      Name        = var.dynamodb_table_name
      Purpose     = "terraform-state-locking"
      Environment = var.environment
      Component   = "backend"
      ManagedBy   = "terraform"
      
      # Compliance and operational tags
      BackupRequired = "true"
      Monitoring     = "enabled"
      
      # Cost optimization tags
      BillingMode = var.dynamodb_billing_mode
      TableClass  = var.dynamodb_table_class
    }
  )

  lifecycle {
    # Prevent accidental deletion in production
    prevent_destroy = var.environment == "prod" ? true : false

    # Ignore changes to read/write capacity if auto-scaling is enabled
    ignore_changes = var.enable_auto_scaling ? [
      read_capacity,
      write_capacity
    ] : []
  }
}

# CloudWatch alarms for DynamoDB monitoring
resource "aws_cloudwatch_metric_alarm" "dynamodb_read_throttles" {
  count = var.enable_monitoring ? 1 : 0

  alarm_name          = "${var.dynamodb_table_name}-read-throttles"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ReadThrottledEvents"
  namespace           = "AWS/DynamoDB"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.read_throttle_threshold
  alarm_description   = "DynamoDB read throttling for Terraform state locks"
  alarm_actions       = var.alarm_actions

  dimensions = {
    TableName = aws_dynamodb_table.terraform_locks.name
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "dynamodb_write_throttles" {
  count = var.enable_monitoring ? 1 : 0

  alarm_name          = "${var.dynamodb_table_name}-write-throttles"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "WriteThrottledEvents"
  namespace           = "AWS/DynamoDB"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.write_throttle_threshold
  alarm_description   = "DynamoDB write throttling for Terraform state locks"
  alarm_actions       = var.alarm_actions

  dimensions = {
    TableName = aws_dynamodb_table.terraform_locks.name
  }

  tags = var.tags
}

# Auto-scaling configuration for DynamoDB table (if enabled)
resource "aws_appautoscaling_target" "dynamodb_table_read_target" {
  count = var.enable_auto_scaling && var.dynamodb_billing_mode == "PROVISIONED" ? 1 : 0

  max_capacity       = var.autoscaling_read_max_capacity
  min_capacity       = var.autoscaling_read_min_capacity
  resource_id        = "table/${aws_dynamodb_table.terraform_locks.name}"
  scalable_dimension = "dynamodb:table:ReadCapacityUnits"
  service_namespace  = "dynamodb"

  tags = var.tags
}

resource "aws_appautoscaling_target" "dynamodb_table_write_target" {
  count = var.enable_auto_scaling && var.dynamodb_billing_mode == "PROVISIONED" ? 1 : 0

  max_capacity       = var.autoscaling_write_max_capacity
  min_capacity       = var.autoscaling_write_min_capacity
  resource_id        = "table/${aws_dynamodb_table.terraform_locks.name}"
  scalable_dimension = "dynamodb:table:WriteCapacityUnits"
  service_namespace  = "dynamodb"

  tags = var.tags
}

resource "aws_appautoscaling_policy" "dynamodb_table_read_policy" {
  count = var.enable_auto_scaling && var.dynamodb_billing_mode == "PROVISIONED" ? 1 : 0

  name               = "${var.dynamodb_table_name}-read-scaling-policy"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.dynamodb_table_read_target[0].resource_id
  scalable_dimension = aws_appautoscaling_target.dynamodb_table_read_target[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.dynamodb_table_read_target[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "DynamoDBReadCapacityUtilization"
    }
    target_value = var.autoscaling_read_target_utilization
  }
}

resource "aws_appautoscaling_policy" "dynamodb_table_write_policy" {
  count = var.enable_auto_scaling && var.dynamodb_billing_mode == "PROVISIONED" ? 1 : 0

  name               = "${var.dynamodb_table_name}-write-scaling-policy"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.dynamodb_table_write_target[0].resource_id
  scalable_dimension = aws_appautoscaling_target.dynamodb_table_write_target[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.dynamodb_table_write_target[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "DynamoDBWriteCapacityUtilization"
    }
    target_value = var.autoscaling_write_target_utilization
  }
}

# Lambda function for automatic cleanup of stale locks (optional safety measure)
resource "aws_lambda_function" "lock_cleanup" {
  count = var.enable_lock_cleanup ? 1 : 0

  filename         = data.archive_file.lock_cleanup_lambda[0].output_path
  function_name    = "${var.dynamodb_table_name}-lock-cleanup"
  role            = aws_iam_role.lock_cleanup_role[0].arn
  handler         = "index.handler"
  runtime         = "python3.9"
  timeout         = 300
  source_code_hash = data.archive_file.lock_cleanup_lambda[0].output_base64sha256

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.terraform_locks.name
      MAX_LOCK_AGE_HOURS = var.max_lock_age_hours
    }
  }

  tags = merge(
    var.tags,
    {
      Name    = "${var.dynamodb_table_name}-lock-cleanup"
      Purpose = "cleanup-stale-terraform-locks"
    }
  )
}

data "archive_file" "lock_cleanup_lambda" {
  count = var.enable_lock_cleanup ? 1 : 0

  type        = "zip"
  output_path = "${path.module}/lock-cleanup.zip"
  
  source {
    content = templatefile("${path.module}/lambda/lock_cleanup.py", {
      table_name = var.dynamodb_table_name
    })
    filename = "index.py"
  }
}

resource "aws_iam_role" "lock_cleanup_role" {
  count = var.enable_lock_cleanup ? 1 : 0

  name = "${var.dynamodb_table_name}-lock-cleanup-role"

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

resource "aws_iam_role_policy" "lock_cleanup_policy" {
  count = var.enable_lock_cleanup ? 1 : 0

  name = "${var.dynamodb_table_name}-lock-cleanup-policy"
  role = aws_iam_role.lock_cleanup_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:Scan",
          "dynamodb:DeleteItem",
          "dynamodb:GetItem"
        ]
        Resource = aws_dynamodb_table.terraform_locks.arn
      },
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

# CloudWatch Event Rule for scheduled lock cleanup
resource "aws_cloudwatch_event_rule" "lock_cleanup_schedule" {
  count = var.enable_lock_cleanup ? 1 : 0

  name                = "${var.dynamodb_table_name}-lock-cleanup-schedule"
  description         = "Scheduled cleanup of stale Terraform locks"
  schedule_expression = "rate(${var.lock_cleanup_schedule})"

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "lock_cleanup_target" {
  count = var.enable_lock_cleanup ? 1 : 0

  rule      = aws_cloudwatch_event_rule.lock_cleanup_schedule[0].name
  target_id = "LockCleanupLambdaTarget"
  arn       = aws_lambda_function.lock_cleanup[0].arn
}

resource "aws_lambda_permission" "allow_cloudwatch_lock_cleanup" {
  count = var.enable_lock_cleanup ? 1 : 0

  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lock_cleanup[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.lock_cleanup_schedule[0].arn
}