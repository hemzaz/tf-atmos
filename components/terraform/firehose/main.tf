# One Kinesis Data Firehose delivery stream per instance, delivering to S3
# (extended_s3), modelled on Cloud Posse's aws-kinesis-firehose-stream
# (https://github.com/cloudposse-terraform-components/aws-kinesis-firehose-stream).
# Deviations from upstream, which reads its bucket and log groups through
# remote state and creates one role with S3 access:
#   - The bucket, source and keys are inputs (wired with !terraform.state in
#     the stacks), not remote-state modules.
#   - Source: direct put (upstream's only mode) or a Kinesis stream, read
#     through a separate source role that can only read that stream.
#   - Encryption: a customer managed key for S3 objects and the log group
#     (upstream's encryption_enabled uses the AWS managed aws/s3 key), and
#     server-side encryption of a direct put stream (CMK when given, else an
#     AWS owned key).
#   - Delivery errors are logged to a log group this component creates
#     (upstream disables delivery logging). Upstream's CloudWatch Logs
#     subscription filters (log groups as producers) are not carried over.
#   - Names follow this repo (<Environment>-<name>), not the null-label id.
#   - Upstream has no record processing, conversion or partitioning. This
#     component adds them as aws_kinesis_firehose_delivery_stream models them:
#     Parquet/ORC conversion against a Glue table (data_format_conversion),
#     dynamic partitioning with JQ metadata extraction (dynamic_partitioning)
#     and a Lambda processor (processor_lambda_arn), each granted to the
#     delivery role on exactly its resources.

locals {
  enabled = var.enabled
  name    = "${var.tags["Environment"]}-${var.name}"

  kinesis_source = local.enabled && var.kinesis_source_stream_arn != null

  # Optional features: the object set and enabled (an Atmos deep merge cannot
  # unset an object, so a stack turns one off with enabled: false).
  conversion           = local.enabled && try(var.data_format_conversion.enabled, false)
  dynamic_partitioning = local.enabled && try(var.dynamic_partitioning.enabled, false)
  lambda_processor     = local.enabled && var.processor_lambda_arn != null

  # The Glue table Firehose reads the schema from: region and catalog default
  # to the component's region and account.
  schema            = local.conversion ? var.data_format_conversion.schema_configuration : null
  schema_region     = local.conversion ? coalesce(local.schema.region, var.region) : null
  schema_catalog_id = local.conversion ? coalesce(local.schema.catalog_id, data.aws_caller_identity.current.account_id) : null
  glue_arn_prefix   = local.conversion ? "arn:${data.aws_partition.current.partition}:glue:${local.schema_region}:${local.schema_catalog_id}" : null

  # Firehose invokes the given (possibly qualified) ARN and reads the
  # function's configuration: grant both the given and the unqualified ARN.
  lambda_unqualified_arn = local.lambda_processor ? join(":", slice(split(":", var.processor_lambda_arn), 0, 7)) : null

  jq_queries = local.dynamic_partitioning ? var.dynamic_partitioning.jq_queries : {}

  # Processors in the order Firehose runs them: the Lambda transform, then
  # JQ partition key extraction on its output, then the record delimiter.
  processors = concat(
    local.lambda_processor ? [{
      type = "Lambda"
      parameters = [
        { name = "LambdaArn", value = var.processor_lambda_arn },
        { name = "BufferSizeInMBs", value = tostring(var.processor_lambda_config.buffer_size_in_mbs) },
        { name = "BufferIntervalInSeconds", value = tostring(var.processor_lambda_config.buffer_interval_in_seconds) },
        { name = "NumberOfRetries", value = tostring(var.processor_lambda_config.number_of_retries) },
      ]
    }] : [],
    length(local.jq_queries) > 0 ? [{
      type = "MetadataExtraction"
      parameters = [
        { name = "MetadataExtractionQuery", value = format("{%s}", join(",", [for k, v in local.jq_queries : "${k}:${v}"])) },
        { name = "JsonParsingEngine", value = "JQ-1.6" },
      ]
    }] : [],
    local.dynamic_partitioning && try(var.dynamic_partitioning.append_delimiter, false) ? [{
      type       = "AppendDelimiterToRecord"
      parameters = []
    }] : [],
  )

  delivery_role_name = "${local.name}-delivery"
  source_role_name   = "${local.name}-source"
  log_group_name     = "/aws/kinesisfirehose/${local.name}"
  log_stream_name    = "DestinationDelivery"

  # Firehose assumes both roles; aws:SourceAccount keeps another account's
  # delivery stream from using them (confused deputy).
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "firehose.amazonaws.com" }
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
      }
    }]
  })
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

resource "aws_cloudwatch_log_group" "this" {
  # checkov:skip=CKV_AWS_338:Retention mirrors the repo's other log groups (log_retention_days, default 90) and is a per-stack cost decision, not a module one.
  count = local.enabled ? 1 : 0

  name              = local.log_group_name
  kms_key_id        = var.kms_key_arn
  retention_in_days = var.log_retention_days

  tags = { Name = local.log_group_name }
}

# Firehose writes to an existing stream; it does not create one.
resource "aws_cloudwatch_log_stream" "delivery" {
  count = local.enabled ? 1 : 0

  name           = local.log_stream_name
  log_group_name = aws_cloudwatch_log_group.this[0].name
}

# Delivery role: write to the destination bucket, encrypt with the key
# through S3 only, and log delivery errors to this stream's log stream; with
# the optional features, read the one Glue table and invoke the one Lambda.
resource "aws_iam_role" "delivery" {
  count = local.enabled ? 1 : 0

  name               = local.delivery_role_name
  assume_role_policy = local.assume_role_policy

  tags = { Name = local.delivery_role_name }

  lifecycle {
    precondition {
      condition     = length(local.name) <= 64 && length(local.delivery_role_name) <= 64
      error_message = "The delivery stream name (<Environment>-<name>, \"${local.name}\") and its role name (\"${local.delivery_role_name}\") must be 64 characters or fewer."
    }
  }
}

resource "aws_iam_role_policy" "delivery" {
  count = local.enabled ? 1 : 0

  name = "delivery"
  role = aws_iam_role.delivery[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Sid      = "S3Bucket"
        Effect   = "Allow"
        Action   = ["s3:GetBucketLocation", "s3:ListBucket", "s3:ListBucketMultipartUploads"]
        Resource = var.s3_bucket_arn
      },
      {
        Sid      = "S3Objects"
        Effect   = "Allow"
        Action   = ["s3:AbortMultipartUpload", "s3:GetObject", "s3:PutObject"]
        Resource = "${var.s3_bucket_arn}/*"
      },
      {
        # The encryption context is the object ARN, or the bucket ARN when
        # the bucket uses an S3 Bucket Key (the s3 component's default).
        Sid      = "KMSThroughS3"
        Effect   = "Allow"
        Action   = ["kms:GenerateDataKey", "kms:Decrypt"]
        Resource = var.kms_key_arn
        Condition = {
          StringEquals = {
            "kms:ViaService" = "s3.${var.region}.amazonaws.com"
          }
          StringLike = {
            "kms:EncryptionContext:aws:s3:arn" = [var.s3_bucket_arn, "${var.s3_bucket_arn}/*"]
          }
        }
      },
      {
        Sid      = "DeliveryLogs"
        Effect   = "Allow"
        Action   = ["logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.this[0].arn}:log-stream:${local.log_stream_name}"
      },
      ],
      # Conversion reads the schema of the one Glue table (the Firehose
      # access-control docs: the catalog, database and table ARNs).
      local.conversion ? [{
        Sid      = "GlueSchema"
        Effect   = "Allow"
        Action   = ["glue:GetTable", "glue:GetTableVersion", "glue:GetTableVersions"]
        Resource = ["${local.glue_arn_prefix}:catalog", "${local.glue_arn_prefix}:database/${local.schema.database_name}", "${local.glue_arn_prefix}:table/${local.schema.database_name}/${local.schema.table_name}"]
      }] : [],
      # An encrypted Data Catalog: Glue decrypts the table metadata with the
      # caller's permissions, so the role needs kms:Decrypt through Glue
      # (without it every record goes to the error prefix).
      local.conversion && try(local.schema.kms_key_arn != null, false) ? [{
        Sid      = "KMSThroughGlue"
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = try(local.schema.kms_key_arn, null)
        Condition = {
          StringEquals = {
            "kms:ViaService" = "glue.${coalesce(local.schema_region, var.region)}.amazonaws.com"
          }
        }
      }] : [],
      local.lambda_processor ? [{
        Sid      = "LambdaProcessor"
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction", "lambda:GetFunctionConfiguration"]
        Resource = distinct([var.processor_lambda_arn, local.lambda_unqualified_arn])
      }] : [],
    )
  })
}

# Source role (Kinesis source only): read the one source stream, and decrypt
# it through Kinesis only.
resource "aws_iam_role" "source" {
  count = local.kinesis_source ? 1 : 0

  name               = local.source_role_name
  assume_role_policy = local.assume_role_policy

  tags = { Name = local.source_role_name }
}

resource "aws_iam_role_policy" "source" {
  count = local.kinesis_source ? 1 : 0

  name = "source"
  role = aws_iam_role.source[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [{
        Sid      = "KinesisRead"
        Effect   = "Allow"
        Action   = ["kinesis:DescribeStream", "kinesis:GetRecords", "kinesis:GetShardIterator", "kinesis:ListShards"]
        Resource = var.kinesis_source_stream_arn
      }],
      var.kinesis_source_kms_key_arn == null ? [] : [{
        Sid      = "KMSThroughKinesis"
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = var.kinesis_source_kms_key_arn
        Condition = {
          StringEquals = {
            "kms:ViaService"                        = "kinesis.${var.region}.amazonaws.com"
            "kms:EncryptionContext:aws:kinesis:arn" = var.kinesis_source_stream_arn
          }
        }
      }]
    )
  })
}

resource "aws_kinesis_firehose_delivery_stream" "this" {
  # checkov:skip=CKV_AWS_241:A direct put stream uses server_side_encryption_kms_key_arn when set; a Kinesis source cannot take stream SSE (its data stays encrypted by the source stream's key).
  count = local.enabled ? 1 : 0

  name        = local.name
  destination = "extended_s3"

  dynamic "kinesis_source_configuration" {
    for_each = local.kinesis_source ? [1] : []
    content {
      kinesis_stream_arn = var.kinesis_source_stream_arn
      role_arn           = aws_iam_role.source[0].arn
    }
  }

  # Direct put streams are always encrypted: with the given CMK, or an AWS
  # owned key. Firehose rejects this block for a Kinesis source.
  dynamic "server_side_encryption" {
    for_each = local.kinesis_source ? [] : [1]
    content {
      enabled  = true
      key_type = var.server_side_encryption_kms_key_arn == null ? "AWS_OWNED_CMK" : "CUSTOMER_MANAGED_CMK"
      key_arn  = var.server_side_encryption_kms_key_arn
    }
  }

  extended_s3_configuration {
    role_arn            = aws_iam_role.delivery[0].arn
    bucket_arn          = var.s3_bucket_arn
    prefix              = var.s3_prefix
    error_output_prefix = var.s3_error_output_prefix
    buffering_size      = var.buffering_size
    buffering_interval  = var.buffering_interval
    compression_format  = var.compression_format
    kms_key_arn         = var.kms_key_arn

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.this[0].name
      log_stream_name = aws_cloudwatch_log_stream.delivery[0].name
    }

    dynamic "processing_configuration" {
      for_each = length(local.processors) > 0 ? [1] : []
      content {
        enabled = true

        dynamic "processors" {
          for_each = local.processors
          content {
            type = processors.value.type

            dynamic "parameters" {
              for_each = processors.value.parameters
              content {
                parameter_name  = parameters.value.name
                parameter_value = parameters.value.value
              }
            }
          }
        }
      }
    }

    dynamic "dynamic_partitioning_configuration" {
      for_each = local.dynamic_partitioning ? [var.dynamic_partitioning] : []
      content {
        enabled        = true
        retry_duration = dynamic_partitioning_configuration.value.retry_duration
      }
    }

    dynamic "data_format_conversion_configuration" {
      for_each = local.conversion ? [var.data_format_conversion] : []
      content {
        enabled = true

        input_format_configuration {
          deserializer {
            dynamic "open_x_json_ser_de" {
              for_each = data_format_conversion_configuration.value.input_format == "OPENX_JSON" ? [data_format_conversion_configuration.value.open_x_json] : []
              content {
                case_insensitive                         = open_x_json_ser_de.value.case_insensitive
                convert_dots_in_json_keys_to_underscores = open_x_json_ser_de.value.convert_dots_in_json_keys_to_underscores
                column_to_json_key_mappings              = open_x_json_ser_de.value.column_to_json_key_mappings
              }
            }

            dynamic "hive_json_ser_de" {
              for_each = data_format_conversion_configuration.value.input_format == "HIVE_JSON" ? [1] : []
              content {
                timestamp_formats = data_format_conversion_configuration.value.hive_json_timestamp_formats
              }
            }
          }
        }

        output_format_configuration {
          serializer {
            dynamic "parquet_ser_de" {
              for_each = data_format_conversion_configuration.value.output_format == "PARQUET" ? [data_format_conversion_configuration.value.parquet] : []
              content {
                compression                   = data_format_conversion_configuration.value.compression
                enable_dictionary_compression = parquet_ser_de.value.enable_dictionary_compression
                block_size_bytes              = parquet_ser_de.value.block_size_bytes
                page_size_bytes               = parquet_ser_de.value.page_size_bytes
                max_padding_bytes             = parquet_ser_de.value.max_padding_bytes
                writer_version                = parquet_ser_de.value.writer_version
              }
            }

            dynamic "orc_ser_de" {
              for_each = data_format_conversion_configuration.value.output_format == "ORC" ? [1] : []
              content {
                compression = data_format_conversion_configuration.value.compression
              }
            }
          }
        }

        schema_configuration {
          database_name = local.schema.database_name
          table_name    = local.schema.table_name
          region        = local.schema_region
          catalog_id    = local.schema_catalog_id
          version_id    = local.schema.version_id
          role_arn      = aws_iam_role.delivery[0].arn
        }
      }
    }
  }

  tags = { Name = local.name }

  # Firehose validates the roles when the stream is created; IAM is
  # eventually consistent, so the policies must exist first.
  depends_on = [aws_iam_role_policy.delivery, aws_iam_role_policy.source]
}
