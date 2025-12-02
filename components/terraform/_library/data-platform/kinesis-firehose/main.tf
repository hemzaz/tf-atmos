##############################################
# Kinesis Firehose Delivery Stream
##############################################

resource "aws_kinesis_firehose_delivery_stream" "main" {
  name        = "${var.name_prefix}-firehose"
  destination = var.destination

  tags = merge(
    var.tags,
    {
      Name      = "${var.name_prefix}-firehose"
      Module    = "kinesis-firehose"
      ManagedBy = "terraform"
    }
  )

  dynamic "kinesis_source_configuration" {
    for_each = var.kinesis_source_stream_arn != null ? [1] : []
    content {
      kinesis_stream_arn = var.kinesis_source_stream_arn
      role_arn           = aws_iam_role.firehose.arn
    }
  }

  dynamic "extended_s3_configuration" {
    for_each = var.destination == "extended_s3" ? [1] : []
    content {
      role_arn            = aws_iam_role.firehose.arn
      bucket_arn          = var.s3_bucket_arn
      prefix              = var.s3_prefix
      error_output_prefix = var.s3_error_prefix
      compression_format  = var.s3_compression_format
      kms_key_arn         = var.kms_key_arn

      buffer_size     = var.buffer_size_mb
      buffer_interval = var.buffer_interval_seconds

      dynamic "processing_configuration" {
        for_each = var.enable_transformation ? [1] : []
        content {
          enabled = true

          processors {
            type = "Lambda"

            parameters {
              parameter_name  = "LambdaArn"
              parameter_value = "${var.transformation_lambda_arn}:$LATEST"
            }
            parameters {
              parameter_name  = "BufferSizeInMBs"
              parameter_value = "3"
            }
            parameters {
              parameter_name  = "BufferIntervalInSeconds"
              parameter_value = "60"
            }
          }
        }
      }

      dynamic "cloudwatch_logging_options" {
        for_each = var.enable_cloudwatch_logs ? [1] : []
        content {
          enabled         = true
          log_group_name  = aws_cloudwatch_log_group.firehose[0].name
          log_stream_name = "S3Delivery"
        }
      }

      dynamic "data_format_conversion_configuration" {
        for_each = var.enable_parquet_conversion ? [1] : []
        content {
          input_format_configuration {
            deserializer {
              open_x_json_ser_de {}
            }
          }

          output_format_configuration {
            serializer {
              parquet_ser_de {}
            }
          }

          schema_configuration {
            database_name = var.glue_database_name
            table_name    = var.glue_table_name
            region        = data.aws_region.current.name
            role_arn      = aws_iam_role.firehose.arn
          }
        }
      }

      dynamic "s3_backup_configuration" {
        for_each = var.enable_s3_backup ? [1] : []
        content {
          role_arn            = aws_iam_role.firehose.arn
          bucket_arn          = var.backup_s3_bucket_arn
          prefix              = var.backup_s3_prefix
          compression_format  = var.s3_compression_format
          buffer_size         = var.buffer_size_mb
          buffer_interval     = var.buffer_interval_seconds
          kms_key_arn         = var.kms_key_arn
        }
      }
    }
  }

  dynamic "opensearch_configuration" {
    for_each = var.destination == "opensearch" ? [1] : []
    content {
      role_arn           = aws_iam_role.firehose.arn
      domain_arn         = var.opensearch_domain_arn
      index_name         = var.opensearch_index_name
      index_rotation_period = var.opensearch_index_rotation
      type_name          = var.opensearch_type_name

      buffering_interval = var.buffer_interval_seconds
      buffering_size     = var.buffer_size_mb

      dynamic "processing_configuration" {
        for_each = var.enable_transformation ? [1] : []
        content {
          enabled = true

          processors {
            type = "Lambda"

            parameters {
              parameter_name  = "LambdaArn"
              parameter_value = "${var.transformation_lambda_arn}:$LATEST"
            }
          }
        }
      }

      dynamic "cloudwatch_logging_options" {
        for_each = var.enable_cloudwatch_logs ? [1] : []
        content {
          enabled         = true
          log_group_name  = aws_cloudwatch_log_group.firehose[0].name
          log_stream_name = "OpenSearchDelivery"
        }
      }

      s3_backup_mode = var.enable_s3_backup ? "AllDocuments" : "FailedDocumentsOnly"

      s3_configuration {
        role_arn            = aws_iam_role.firehose.arn
        bucket_arn          = var.backup_s3_bucket_arn
        prefix              = var.backup_s3_prefix
        compression_format  = var.s3_compression_format
        buffer_size         = var.buffer_size_mb
        buffer_interval     = var.buffer_interval_seconds
        kms_key_arn         = var.kms_key_arn
      }
    }
  }

  dynamic "redshift_configuration" {
    for_each = var.destination == "redshift" ? [1] : []
    content {
      role_arn           = aws_iam_role.firehose.arn
      cluster_jdbcurl    = var.redshift_cluster_jdbcurl
      username           = var.redshift_username
      password           = var.redshift_password
      data_table_name    = var.redshift_table_name
      copy_options       = var.redshift_copy_options
      data_table_columns = var.redshift_table_columns

      s3_configuration {
        role_arn            = aws_iam_role.firehose.arn
        bucket_arn          = var.s3_bucket_arn
        prefix              = var.s3_prefix
        compression_format  = var.s3_compression_format
        buffer_size         = var.buffer_size_mb
        buffer_interval     = var.buffer_interval_seconds
        kms_key_arn         = var.kms_key_arn
      }

      dynamic "processing_configuration" {
        for_each = var.enable_transformation ? [1] : []
        content {
          enabled = true

          processors {
            type = "Lambda"

            parameters {
              parameter_name  = "LambdaArn"
              parameter_value = "${var.transformation_lambda_arn}:$LATEST"
            }
          }
        }
      }

      dynamic "cloudwatch_logging_options" {
        for_each = var.enable_cloudwatch_logs ? [1] : []
        content {
          enabled         = true
          log_group_name  = aws_cloudwatch_log_group.firehose[0].name
          log_stream_name = "RedshiftDelivery"
        }
      }
    }
  }
}

##############################################
# IAM Role for Firehose
##############################################

resource "aws_iam_role" "firehose" {
  name = "${var.name_prefix}-firehose-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "firehose.amazonaws.com"
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "firehose" {
  name = "${var.name_prefix}-firehose-policy"
  role = aws_iam_role.firehose.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Effect = "Allow"
          Action = [
            "s3:AbortMultipartUpload",
            "s3:GetBucketLocation",
            "s3:GetObject",
            "s3:ListBucket",
            "s3:ListBucketMultipartUploads",
            "s3:PutObject"
          ]
          Resource = [
            var.s3_bucket_arn,
            "${var.s3_bucket_arn}/*"
          ]
        }
      ],
      var.kinesis_source_stream_arn != null ? [
        {
          Effect = "Allow"
          Action = [
            "kinesis:DescribeStream",
            "kinesis:GetShardIterator",
            "kinesis:GetRecords",
            "kinesis:ListShards"
          ]
          Resource = var.kinesis_source_stream_arn
        }
      ] : [],
      var.kms_key_arn != null ? [
        {
          Effect = "Allow"
          Action = [
            "kms:Decrypt",
            "kms:GenerateDataKey"
          ]
          Resource = var.kms_key_arn
        }
      ] : [],
      var.enable_transformation ? [
        {
          Effect = "Allow"
          Action = [
            "lambda:InvokeFunction",
            "lambda:GetFunctionConfiguration"
          ]
          Resource = "${var.transformation_lambda_arn}:*"
        }
      ] : [],
      var.enable_cloudwatch_logs ? [
        {
          Effect = "Allow"
          Action = [
            "logs:PutLogEvents"
          ]
          Resource = "${aws_cloudwatch_log_group.firehose[0].arn}:*"
        }
      ] : [],
      var.enable_parquet_conversion ? [
        {
          Effect = "Allow"
          Action = [
            "glue:GetTable",
            "glue:GetTableVersion",
            "glue:GetTableVersions"
          ]
          Resource = [
            "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:catalog",
            "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:database/${var.glue_database_name}",
            "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/${var.glue_database_name}/${var.glue_table_name}"
          ]
        }
      ] : []
    )
  })
}

##############################################
# CloudWatch Log Group
##############################################

resource "aws_cloudwatch_log_group" "firehose" {
  count = var.enable_cloudwatch_logs ? 1 : 0

  name              = "/aws/kinesisfirehose/${var.name_prefix}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = merge(
    var.tags,
    {
      Name      = "${var.name_prefix}-firehose-logs"
      ManagedBy = "terraform"
    }
  )
}

resource "aws_cloudwatch_log_stream" "firehose" {
  for_each = var.enable_cloudwatch_logs ? toset(["S3Delivery", "OpenSearchDelivery", "RedshiftDelivery"]) : []

  name           = each.value
  log_group_name = aws_cloudwatch_log_group.firehose[0].name
}

##############################################
# CloudWatch Alarms
##############################################

resource "aws_cloudwatch_metric_alarm" "delivery_to_s3_failed" {
  count = var.enable_monitoring ? 1 : 0

  alarm_name          = "${var.name_prefix}-firehose-delivery-failed"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DeliveryToS3.DataFreshness"
  namespace           = "AWS/Firehose"
  period              = 300
  statistic           = "Maximum"
  threshold           = 900
  alarm_description   = "Firehose delivery is failing or delayed"
  alarm_actions       = var.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    DeliveryStreamName = aws_kinesis_firehose_delivery_stream.main.name
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "throttled_records" {
  count = var.enable_monitoring ? 1 : 0

  alarm_name          = "${var.name_prefix}-firehose-throttled"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ThrottledRecords"
  namespace           = "AWS/Firehose"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "Firehose is throttling records"
  alarm_actions       = var.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    DeliveryStreamName = aws_kinesis_firehose_delivery_stream.main.name
  }

  tags = var.tags
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
