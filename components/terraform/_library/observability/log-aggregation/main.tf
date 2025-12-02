##############################################
# Central Log Group
##############################################

resource "aws_cloudwatch_log_group" "central" {
  name              = "/aws/centralized/${var.name_prefix}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_id

  tags = merge(
    var.tags,
    {
      Name      = "${var.name_prefix}-central-logs"
      ManagedBy = "terraform"
    }
  )
}

##############################################
# Log Groups by Service
##############################################

resource "aws_cloudwatch_log_group" "services" {
  for_each = var.service_log_groups

  name              = "/aws/${each.key}/${var.name_prefix}"
  retention_in_days = lookup(each.value, "retention_days", var.log_retention_days)
  kms_key_id        = var.kms_key_id

  tags = merge(
    var.tags,
    {
      Name      = "${var.name_prefix}-${each.key}"
      Service   = each.key
      ManagedBy = "terraform"
    }
  )
}

##############################################
# Subscription Filters to Kinesis
##############################################

resource "aws_kinesis_stream" "logs" {
  count = var.enable_kinesis_streaming ? 1 : 0

  name             = "${var.name_prefix}-logs"
  shard_count      = var.kinesis_shard_count
  retention_period = var.kinesis_retention_hours

  stream_mode_details {
    stream_mode = var.kinesis_on_demand ? "ON_DEMAND" : "PROVISIONED"
  }

  encryption_type = "KMS"
  kms_key_id      = var.kms_key_id

  tags = merge(
    var.tags,
    {
      Name      = "${var.name_prefix}-logs"
      ManagedBy = "terraform"
    }
  )
}

resource "aws_cloudwatch_log_subscription_filter" "kinesis" {
  for_each = var.enable_kinesis_streaming ? var.service_log_groups : {}

  name            = "${var.name_prefix}-${each.key}-to-kinesis"
  log_group_name  = aws_cloudwatch_log_group.services[each.key].name
  filter_pattern  = lookup(each.value, "filter_pattern", "")
  destination_arn = aws_kinesis_stream.logs[0].arn
  role_arn        = aws_iam_role.cloudwatch_to_kinesis[0].arn

  depends_on = [aws_iam_role_policy.cloudwatch_to_kinesis]
}

##############################################
# S3 Export Configuration
##############################################

resource "aws_s3_bucket" "logs" {
  count = var.enable_s3_export ? 1 : 0

  bucket = "${var.name_prefix}-logs-${data.aws_caller_identity.current.account_id}"

  tags = merge(
    var.tags,
    {
      Name      = "${var.name_prefix}-logs"
      ManagedBy = "terraform"
    }
  )
}

resource "aws_s3_bucket_versioning" "logs" {
  count = var.enable_s3_export ? 1 : 0

  bucket = aws_s3_bucket.logs[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  count = var.enable_s3_export ? 1 : 0

  bucket = aws_s3_bucket.logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_id
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  count = var.enable_s3_export ? 1 : 0

  bucket = aws_s3_bucket.logs[0].id

  rule {
    id     = "archive-old-logs"
    status = "Enabled"

    transition {
      days          = var.s3_transition_to_ia_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.s3_transition_to_glacier_days
      storage_class = "GLACIER"
    }

    expiration {
      days = var.s3_expiration_days
    }
  }
}

##############################################
# Lambda for S3 Export
##############################################

resource "aws_lambda_function" "export_to_s3" {
  count = var.enable_s3_export ? 1 : 0

  filename      = "${path.module}/templates/export_logs.zip"
  function_name = "${var.name_prefix}-export-logs"
  role          = aws_iam_role.export_lambda[0].arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 300

  environment {
    variables = {
      S3_BUCKET        = aws_s3_bucket.logs[0].id
      LOG_GROUP_PREFIX = "/aws/"
    }
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-export-logs"
    }
  )
}

resource "aws_cloudwatch_event_rule" "export_schedule" {
  count = var.enable_s3_export ? 1 : 0

  name                = "${var.name_prefix}-export-schedule"
  description         = "Schedule for log export to S3"
  schedule_expression = var.export_schedule

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "export_lambda" {
  count = var.enable_s3_export ? 1 : 0

  rule      = aws_cloudwatch_event_rule.export_schedule[0].name
  target_id = "ExportLambda"
  arn       = aws_lambda_function.export_to_s3[0].arn
}

resource "aws_lambda_permission" "cloudwatch_events" {
  count = var.enable_s3_export ? 1 : 0

  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.export_to_s3[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.export_schedule[0].arn
}

##############################################
# Athena Query Setup
##############################################

resource "aws_athena_workgroup" "logs" {
  count = var.enable_athena_queries ? 1 : 0

  name = "${var.name_prefix}-logs"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.logs[0].id}/athena-results/"

      encryption_configuration {
        encryption_option = "SSE_KMS"
        kms_key           = var.kms_key_id
      }
    }
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-logs"
    }
  )
}

resource "aws_athena_database" "logs" {
  count = var.enable_athena_queries ? 1 : 0

  name   = replace("${var.name_prefix}_logs", "-", "_")
  bucket = aws_s3_bucket.logs[0].id

  encryption_configuration {
    encryption_option = "SSE_KMS"
    kms_key           = var.kms_key_id
  }
}

##############################################
# Metric Filters
##############################################

resource "aws_cloudwatch_log_metric_filter" "error_count" {
  count = var.create_error_metric_filter ? 1 : 0

  name           = "${var.name_prefix}-error-count"
  pattern        = var.error_filter_pattern
  log_group_name = aws_cloudwatch_log_group.central.name

  metric_transformation {
    name      = "ErrorCount"
    namespace = var.custom_metric_namespace
    value     = "1"
    unit      = "Count"
  }
}

resource "aws_cloudwatch_log_metric_filter" "custom" {
  for_each = var.custom_metric_filters

  name           = "${var.name_prefix}-${each.key}"
  pattern        = each.value.pattern
  log_group_name = aws_cloudwatch_log_group.central.name

  metric_transformation {
    name      = each.value.metric_name
    namespace = var.custom_metric_namespace
    value     = each.value.value
    unit      = lookup(each.value, "unit", "None")
  }
}

##############################################
# IAM Roles
##############################################

resource "aws_iam_role" "cloudwatch_to_kinesis" {
  count = var.enable_kinesis_streaming ? 1 : 0

  name = "${var.name_prefix}-cloudwatch-to-kinesis"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "logs.amazonaws.com"
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "cloudwatch_to_kinesis" {
  count = var.enable_kinesis_streaming ? 1 : 0

  name = "${var.name_prefix}-cloudwatch-to-kinesis"
  role = aws_iam_role.cloudwatch_to_kinesis[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "kinesis:PutRecord",
        "kinesis:PutRecords"
      ]
      Resource = aws_kinesis_stream.logs[0].arn
    }]
  })
}

resource "aws_iam_role" "export_lambda" {
  count = var.enable_s3_export ? 1 : 0

  name = "${var.name_prefix}-export-lambda"

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

  tags = var.tags
}

resource "aws_iam_role_policy" "export_lambda" {
  count = var.enable_s3_export ? 1 : 0

  name = "${var.name_prefix}-export-lambda"
  role = aws_iam_role.export_lambda[0].id

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
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateExportTask",
          "logs:DescribeExportTasks"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        Resource = "${aws_s3_bucket.logs[0].arn}/*"
      }
    ]
  })
}

##############################################
# Data Sources
##############################################

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
