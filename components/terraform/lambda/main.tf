# components/terraform/lambda/main.tf
# Only fetched when actually needed: an unconditional data source here would
# make every plan of this component call STS GetCallerIdentity, which breaks
# the fully offline test suite in tests/ (dummy credentials, no real AWS
# call ever made) for every run, not just ones that set secretsmanager_source_arn,
# s3_source_arn, kms_key_arn or rotation_secret_arn.
data "aws_caller_identity" "current" {
  count = var.secretsmanager_source_arn != null || var.s3_source_arn != null || var.kms_key_arn != null || var.rotation_secret_arn != null ? 1 : 0
}

locals {
  # aws_lambda_function.main.arn is Computed by the AWS provider -- unknown
  # at plan time -- even though a Lambda ARN is fully deterministic (no
  # AWS-assigned random element, unlike e.g. ElastiCache's cluster-mode
  # endpoint hostname). Built here instead so the KMS environment-variable
  # decrypt grant and rotation_lambda_arn below stay plannable without an
  # apply, the same reasoning the microservices-platform template used to
  # spell this same ARN out as a literal string before rotation moved into
  # this component's own aws_secretsmanager_secret_rotation.
  function_arn = var.kms_key_arn != null || var.rotation_secret_arn != null ? "arn:aws:lambda:${var.region}:${data.aws_caller_identity.current[0].account_id}:function:${aws_lambda_function.main.function_name}" : null
}

# In-component packaging for small, in-repo function sources (see
# var.source_dir's description). Zips ${path.module}/${var.source_dir} at
# plan time; external build pipelines keep using filename or s3_bucket+s3_key
# instead, both left untouched by this.
data "archive_file" "source" {
  count       = var.source_dir != null ? 1 : 0
  type        = "zip"
  source_dir  = "${path.module}/${var.source_dir}"
  output_path = "${path.module}/.archives/${var.function_name}.zip"
  # Pinned so output_base64sha256 depends only on file content, not on the
  # file modes a checkout happens to produce -- macOS and the Linux CI
  # container can otherwise zip the same source_dir to different hashes,
  # causing a perpetual source_code_hash diff (or an unwanted redeploy
  # between plan and apply). Cloud Posse's own aws-lambda component pins this
  # too on its zip/archive_file path.
  output_file_mode = "0644"
}

locals {
  # Exactly one of these three ends up non-null for a Zip package; the
  # precondition on aws_lambda_function.main below enforces that.
  package_filename         = var.source_dir != null ? data.archive_file.source[0].output_path : var.filename
  package_source_code_hash = var.source_dir != null ? data.archive_file.source[0].output_base64sha256 : var.source_code_hash
}

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

  tags = { Name = "${var.tags["Environment"]}-${var.function_name}-role" }
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

# Condition is only rendered when a statement sets conditions, grouped by test
# operator and then condition key (as in the stepfunctions component); Sid
# only when set.
resource "aws_iam_role_policy" "lambda_iam_policies" {
  count = length(var.iam_policies) > 0 ? 1 : 0
  name  = "${var.tags["Environment"]}-${var.function_name}-iam-policies"
  role  = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [for s in var.iam_policies : merge(
      s.sid != null ? { Sid = s.sid } : {},
      {
        Effect   = coalesce(s.effect, "Allow")
        Action   = s.actions
        Resource = s.resources
      },
      length(coalesce(s.conditions, [])) > 0 ? {
        Condition = {
          for test in distinct([for c in s.conditions : c.test]) :
          test => { for c in s.conditions : c.variable => c.values if c.test == test }
        }
      } : {}
    )]
  })
}

# kms_key_arn (below, on aws_lambda_function.main) tells Lambda to encrypt
# this function's environment variables with a customer managed key instead
# of the AWS-owned default. Lambda decrypts them as the function's own
# execution role at invoke time, using an encryption context of
# aws:lambda:FunctionArn -- so, unlike the AWS-owned default key, this role
# needs an explicit kms:Decrypt grant, or every invocation fails with "KMS
# access was denied" the moment an environment variable is read.
resource "aws_iam_role_policy" "lambda_kms_env" {
  count = var.kms_key_arn != null ? 1 : 0
  name  = "${var.tags["Environment"]}-${var.function_name}-kms-env"
  role  = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "AllowEnvironmentVariableDecryption"
      Effect   = "Allow"
      Action   = ["kms:Decrypt"]
      Resource = var.kms_key_arn
      Condition = {
        StringEquals = {
          "kms:EncryptionContext:aws:lambda:FunctionArn" = local.function_arn
        }
      }
    }]
  })
}

# Lambda delivers to asynchronous-invocation destinations, to the dead letter
# target and to a stream event source mapping's on_failure destination as the
# function's execution role, so the role must be allowed to send to each SQS
# queue / publish to each SNS topic named there (and, for one encrypted with a
# customer managed key, to use that key).
locals {
  esm_failure_destinations = [for m in values(var.event_source_mappings) : m.destination_config.on_failure.destination_arn if m.destination_config != null]

  delivery_targets    = distinct(concat(compact([var.on_success_destination, var.on_failure_destination, var.dead_letter_target_arn]), local.esm_failure_destinations))
  delivery_queue_arns = [for a in local.delivery_targets : a if try(split(":", a)[2], "") == "sqs"]
  delivery_topic_arns = [for a in local.delivery_targets : a if try(split(":", a)[2], "") == "sns"]
  delivery_policy     = length(local.delivery_queue_arns) + length(local.delivery_topic_arns) > 0
}

data "aws_iam_policy_document" "delivery" {
  count = local.delivery_policy ? 1 : 0

  dynamic "statement" {
    for_each = length(local.delivery_queue_arns) > 0 ? [1] : []
    content {
      sid       = "SendToDeliveryQueues"
      actions   = ["sqs:SendMessage"]
      resources = local.delivery_queue_arns
    }
  }

  dynamic "statement" {
    for_each = length(local.delivery_topic_arns) > 0 ? [1] : []
    content {
      sid       = "PublishToDeliveryTopics"
      actions   = ["sns:Publish"]
      resources = local.delivery_topic_arns
    }
  }

  dynamic "statement" {
    for_each = var.delivery_kms_key_arn != null ? [1] : []
    content {
      sid       = "UseDeliveryKey"
      actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
      resources = [var.delivery_kms_key_arn]
    }
  }
}

resource "aws_iam_role_policy" "delivery" {
  count  = local.delivery_policy ? 1 : 0
  name   = "${var.tags["Environment"]}-${var.function_name}-delivery"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.delivery[0].json
}

# Event source mappings poll their source as the function's execution role,
# so the role needs read access to each queue / stream. Derived from the
# mapping ARNs and scoped to exactly them, unlike AWS's managed
# AWSLambdaSQSQueueExecutionRole / AWSLambdaKinesisExecutionRole /
# AWSLambdaDynamoDBExecutionRole, which grant the same reads on "*".
# A Kinesis consumer ARN (enhanced fan-out) also needs its stream's ARN for
# the stream-level reads, so both are granted. kinesis:ListStreams and
# dynamodb:ListStreams are left out: they only take Resource "*", so a scoped
# grant never matches, and Lambda's poller does not need them (AWS
# services-kinesis-create.html; kinesis/main.tf omits it too).
locals {
  esm_service = { for k, m in var.event_source_mappings : k => split(":", m.event_source_arn)[2] }

  esm_sqs_arns = distinct([for k, m in var.event_source_mappings : m.event_source_arn if local.esm_service[k] == "sqs"])
  esm_kinesis_arns = distinct(flatten([
    for k, m in var.event_source_mappings : [m.event_source_arn, regex("^(.+:stream/[^/]+)", m.event_source_arn)[0]] if local.esm_service[k] == "kinesis"
  ]))
  esm_dynamodb_arns = distinct([for k, m in var.event_source_mappings : m.event_source_arn if local.esm_service[k] == "dynamodb"])
}

data "aws_iam_policy_document" "event_sources" {
  count = length(var.event_source_mappings) > 0 ? 1 : 0

  dynamic "statement" {
    for_each = length(local.esm_sqs_arns) > 0 ? [1] : []
    content {
      sid       = "ReadSqsEventSources"
      actions   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes", "sqs:ChangeMessageVisibility"]
      resources = local.esm_sqs_arns
    }
  }

  dynamic "statement" {
    for_each = length(local.esm_kinesis_arns) > 0 ? [1] : []
    content {
      sid = "ReadKinesisEventSources"
      actions = [
        "kinesis:DescribeStream",
        "kinesis:DescribeStreamSummary",
        "kinesis:DescribeStreamConsumer",
        "kinesis:GetRecords",
        "kinesis:GetShardIterator",
        "kinesis:ListShards",
        "kinesis:SubscribeToShard",
      ]
      resources = local.esm_kinesis_arns
    }
  }

  dynamic "statement" {
    for_each = length(local.esm_dynamodb_arns) > 0 ? [1] : []
    content {
      sid       = "ReadDynamoDBEventSources"
      actions   = ["dynamodb:DescribeStream", "dynamodb:GetRecords", "dynamodb:GetShardIterator"]
      resources = local.esm_dynamodb_arns
    }
  }

  dynamic "statement" {
    for_each = length(var.event_source_kms_key_arns) > 0 ? [1] : []
    content {
      sid       = "DecryptEventSources"
      actions   = ["kms:Decrypt"]
      resources = var.event_source_kms_key_arns
    }
  }
}

resource "aws_iam_role_policy" "event_sources" {
  count  = length(var.event_source_mappings) > 0 ? 1 : 0
  name   = "${var.tags["Environment"]}-${var.function_name}-event-sources"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.event_sources[0].json
}

# Create log group before the Lambda function to avoid circular dependencies
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.tags["Environment"]}-${var.function_name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_id

  tags = { Name = "/aws/lambda/${var.tags["Environment"]}-${var.function_name}" }
}

# The S3 managed prefix list is AWS-managed and present in every region without
# requiring a VPC endpoint to exist. Its entries are S3's public CIDRs, which is
# exactly what a private-subnet Lambda reaches through the NAT gateway. Resolved
# here so a stack does not have to hardcode a region-specific pl-* id in every
# lambda instance; set vpc_endpoint_prefix_list_ids to override (for example
# when real interface endpoints exist and egress should be confined to them).
data "aws_ec2_managed_prefix_list" "s3" {
  count = length(var.subnet_ids) > 0 && length(var.vpc_endpoint_prefix_list_ids) == 0 ? 1 : 0
  name  = "com.amazonaws.${var.region}.s3"
}

locals {
  # Empty means "resolve the region's S3 prefix list", never "allow nothing":
  # an egress rule with an empty prefix_list_ids permits no traffic at all.
  vpc_endpoint_prefix_list_ids = length(var.vpc_endpoint_prefix_list_ids) > 0 ? var.vpc_endpoint_prefix_list_ids : data.aws_ec2_managed_prefix_list.s3[*].id
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
    prefix_list_ids = local.vpc_endpoint_prefix_list_ids
  }

  # Only allow HTTP if explicitly enabled (not recommended for production)
  dynamic "egress" {
    for_each = var.allow_http_egress ? [1] : []
    content {
      description     = "HTTP for package downloads (only if explicitly enabled)"
      from_port       = 80
      to_port         = 80
      protocol        = "tcp"
      prefix_list_ids = local.vpc_endpoint_prefix_list_ids
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

  tags = { Name = "${var.tags["Environment"]}-${var.function_name}-sg" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lambda_function" "main" {
  function_name     = "${var.tags["Environment"]}-${var.function_name}"
  role              = aws_iam_role.lambda.arn
  handler           = var.handler
  runtime           = var.runtime
  filename          = local.package_filename
  source_code_hash  = local.package_source_code_hash
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
      security_group_ids = concat([aws_security_group.lambda[0].id], var.additional_security_group_ids)
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

  package_type  = var.package_type
  architectures = var.architectures

  tags = { Name = "${var.tags["Environment"]}-${var.function_name}" }

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

    # Exactly one packaging source for a Zip package (image packages carry
    # no filename at all -- see the image_config block below).
    precondition {
      condition = (
        var.package_type == "Image" ||
        (var.source_dir != null ? 1 : 0) + (var.filename != null ? 1 : 0) + (var.s3_bucket != null ? 1 : 0) == 1
      )
      error_message = "Exactly one of source_dir, filename or s3_bucket (with s3_key) must be set for a Zip package."
    }
  }
}

resource "aws_lambda_permission" "secretsmanager" {
  count          = var.secretsmanager_source_arn != null ? 1 : 0
  statement_id   = "AllowSecretsManagerInvoke"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.main.function_name
  principal      = "secretsmanager.amazonaws.com"
  source_arn     = var.secretsmanager_source_arn
  source_account = data.aws_caller_identity.current[0].account_id
}

# Configures rotation_secret_arn's rotation from THIS component instance, not
# the secretsmanager component -- see rotation_secret_arn's own description
# for why. depends_on the invoke permission above AND every IAM grant the
# function's own execution role needs (lambda_custom, lambda_kms_env,
# lambda_basic, lambda_vpc_access): Secrets Manager's RotateSecret API (which
# creating/updating this resource calls) invokes the function -- at minimum
# running its testSecret step against a temporary AWSPENDING version it
# creates and then removes, even when rotate_immediately is false, and the
# function's own handler starts with describe_secret/get_secret_value calls
# that need those grants. aws_lambda_function.main only has an IMPLICIT
# dependency on aws_iam_role.lambda (via its arn), not on the role's
# policies -- attaching a policy to a role is a separate resource that does
# not block the role, or anything referencing it, from being usable. Without
# these explicit depends_on, Terraform can create this resource (and AWS can
# invoke the function) before those policies exist or have propagated,
# failing the function's first call with AccessDenied.
resource "aws_secretsmanager_secret_rotation" "this" {
  count = var.rotation_secret_arn != null ? 1 : 0

  secret_id           = var.rotation_secret_arn
  rotation_lambda_arn = local.function_arn
  rotate_immediately  = var.rotate_immediately

  rotation_rules {
    automatically_after_days = var.rotation_days
  }

  depends_on = [
    aws_lambda_permission.secretsmanager,
    aws_iam_role_policy.lambda_custom,
    aws_iam_role_policy.lambda_kms_env,
    aws_iam_role_policy_attachment.lambda_basic,
    aws_iam_role_policy_attachment.lambda_vpc_access,
  ]

  lifecycle {
    precondition {
      condition     = var.secretsmanager_source_arn != null && var.secretsmanager_source_arn == var.rotation_secret_arn
      error_message = "rotation_secret_arn requires secretsmanager_source_arn to be set to the SAME secret's ARN, so this function is actually permitted to be invoked by Secrets Manager before rotation is configured on it."
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
  # A bucket ARN carries no account, and bucket names are global: if this
  # bucket were deleted, another account could create one with the same name
  # and invoke the function. source_account pins the bucket's owner
  # (https://docs.aws.amazon.com/lambda/latest/dg/with-s3.html and the
  # AddPermission SourceAccount parameter).
  source_account = data.aws_caller_identity.current[0].account_id
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

  # AWS checks that the execution role may reach the destinations.
  depends_on = [aws_iam_role_policy.delivery]

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

resource "aws_lambda_event_source_mapping" "this" {
  for_each = var.event_source_mappings

  function_name                      = aws_lambda_function.main.function_name
  event_source_arn                   = each.value.event_source_arn
  enabled                            = each.value.enabled
  batch_size                         = each.value.batch_size
  maximum_batching_window_in_seconds = each.value.maximum_batching_window_in_seconds
  starting_position                  = each.value.starting_position
  starting_position_timestamp        = each.value.starting_position_timestamp
  function_response_types            = length(each.value.function_response_types) > 0 ? each.value.function_response_types : null
  maximum_retry_attempts             = each.value.maximum_retry_attempts
  maximum_record_age_in_seconds      = each.value.maximum_record_age_in_seconds
  bisect_batch_on_function_error     = each.value.bisect_batch_on_function_error
  parallelization_factor             = each.value.parallelization_factor
  tumbling_window_in_seconds         = each.value.tumbling_window_in_seconds

  dynamic "filter_criteria" {
    for_each = each.value.filter_criteria != null ? [each.value.filter_criteria] : []
    content {
      dynamic "filter" {
        for_each = filter_criteria.value.filter
        content {
          pattern = filter.value.pattern
        }
      }
    }
  }

  dynamic "scaling_config" {
    for_each = each.value.scaling_config != null ? [each.value.scaling_config] : []
    content {
      maximum_concurrency = scaling_config.value.maximum_concurrency
    }
  }

  dynamic "destination_config" {
    for_each = each.value.destination_config != null ? [each.value.destination_config] : []
    content {
      on_failure {
        destination_arn = destination_config.value.on_failure.destination_arn
      }
    }
  }

  tags = { Name = "${var.tags["Environment"]}-${var.function_name}-${each.key}" }

  # CreateEventSourceMapping checks that the execution role can read the
  # source (and reach the on_failure destination) before it accepts the
  # mapping, so the grants must exist first.
  depends_on = [aws_iam_role_policy.event_sources, aws_iam_role_policy.delivery]
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
}

# Cost optimization: Schedule for predictable workloads
resource "aws_cloudwatch_event_rule" "lambda_schedule" {
  count = var.schedule_expression != null ? 1 : 0

  name                = "${var.tags["Environment"]}-${var.function_name}-schedule"
  description         = "Schedule for Lambda function ${var.function_name}"
  schedule_expression = var.schedule_expression
  state               = var.schedule_enabled ? "ENABLED" : "DISABLED"
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
