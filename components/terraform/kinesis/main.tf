# One Kinesis Data Stream per instance, modelled on Cloud Posse's
# aws-kinesis-stream component (https://github.com/cloudposse-terraform-components/aws-kinesis-stream,
# which wraps cloudposse/terraform-aws-kinesis-stream). Written as a plain
# resource, like the other short-name root components (stepfunctions, sns,
# sqs). Encryption is always KMS (there is no NONE/unencrypted option here,
# unlike the upstream module): callers always supply kms_key_id.
#
# Enhanced fan-out consumers (aws_kinesis_stream_consumer) are created from
# the `consumers` map, one per key, each independently toggleable.
#
# This component has no reader role of its own to grant kms:Decrypt to (a
# Lambda event source mapping, a Firehose delivery stream, ... each has its
# own), so it exposes a ready-to-use IAM policy document as the
# reader_kms_policy output instead: the same Resource/Condition pair AWS's own
# docs show for granting a Kinesis reader (e.g. Firehose reading an encrypted
# source stream) kms:Decrypt, scoped to this stream's own encryption context.
# Consumers wire it in via !terraform.state into whatever custom/inline
# policy input their own component exposes (e.g. the lambda component's
# custom_policy).

locals {
  enabled = var.enabled
  name    = "${var.tags["Environment"]}-${var.name}"

  consumers = local.enabled ? { for k, v in var.consumers : k => v if v.enabled } : {}
}

resource "aws_kinesis_stream" "this" {
  count = local.enabled ? 1 : 0

  name                      = local.name
  retention_period          = var.retention_period
  shard_count               = var.stream_mode == "PROVISIONED" ? var.shard_count : null
  shard_level_metrics       = var.shard_level_metrics
  enforce_consumer_deletion = var.enforce_consumer_deletion

  encryption_type = "KMS"
  kms_key_id      = var.kms_key_id

  stream_mode_details {
    stream_mode = var.stream_mode
  }

  tags = { Name = local.name }
}

resource "aws_kinesis_stream_consumer" "this" {
  for_each = local.consumers

  name       = each.key
  stream_arn = one(aws_kinesis_stream.this[*].arn)
}

# The stream ARN is only known once the resource above exists (`one(...)`
# returns null pre-apply on a fresh create, and always null when disabled),
# so this is computed after it rather than alongside the other locals.
locals {
  reader_kms_policy = local.enabled ? jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "AllowKinesisStreamKMSRead"
      Effect   = "Allow"
      Action   = ["kms:Decrypt"]
      Resource = var.kms_key_id
      Condition = {
        StringEquals = {
          "kms:ViaService"                        = "kinesis.${var.region}.amazonaws.com"
          "kms:EncryptionContext:aws:kinesis:arn" = one(aws_kinesis_stream.this[*].arn)
        }
      }
    }]
  }) : null
}
