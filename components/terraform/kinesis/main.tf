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
# This component has no reader/writer role of its own to grant permissions to
# (a Lambda event source mapping, a Firehose delivery stream, an application
# calling PutRecord[s], ... each has its own), so it exposes ready-to-use IAM
# policy documents instead:
#   - reader_policy: the Kinesis actions a consumer needs to read the stream
#     (GetRecords/GetShardIterator/DescribeStream[Summary]/ListShards, plus
#     SubscribeToShard/DescribeStreamConsumer on any enhanced fan-out
#     consumer ARNs), plus kms:Decrypt scoped to this stream's own
#     encryption context - the same Resource/Condition pair AWS's own docs
#     show for granting a Kinesis reader (e.g. Firehose reading an encrypted
#     source stream) kms:Decrypt. (ListStreams is deliberately not included:
#     it supports no resource-level permissions, so scoping it to this
#     stream's ARN would never actually grant it.)
#   - writer_policy: the Kinesis actions a producer needs to write to the
#     stream (PutRecord/PutRecords/DescribeStreamSummary), plus
#     kms:GenerateDataKey scoped the same way (a KMS-encrypted stream's
#     producer needs to generate a data key to encrypt each record). Always
#     exactly these two statements - see combined_policy below for a version
#     that also carries another stream's grants.
# Consumers wire the relevant output in via !terraform.state into whatever
# custom/inline policy input their own component exposes (e.g. the lambda
# component's custom_policy).
#
# A single consumer that needs grants on TWO different streams (e.g. a
# Lambda function that reads one stream and writes another, whose
# custom_policy input accepts only one policy document) can't get there with
# !terraform.state alone - it reads one component's one output, never
# combines two components' outputs into one value. additional_policy_json
# closes that gap without an Atmos Go template (atmos.Component can combine
# two components' outputs, but doing so requires live state even at
# `atmos describe`/`validate stacks` time, breaking those commands for the
# whole stack before anything in it has ever been applied): set it, via
# !terraform.state, to the OTHER stream's own reader_policy/writer_policy
# output, and this stream's combined_policy output folds its Statement
# entries in alongside writer_policy's own two - writer_policy itself stays
# pure (exactly its own two statements) so attaching it never silently grants
# more than "write to this stream". Each folded-in statement's Sid is
# rewritten (prefixed "Additional<n>") so it can never collide with
# writer_policy's own Sids or with another folded-in statement's, even if
# additional_policy_json is itself a writer_policy-shaped document whose Sids
# would otherwise repeat this stream's own.

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
  stream_arn    = one(aws_kinesis_stream.this[*].arn)
  consumer_arns = [for c in aws_kinesis_stream_consumer.this : c.arn]

  kms_condition = {
    StringEquals = {
      "kms:ViaService"                        = "kinesis.${var.region}.amazonaws.com"
      "kms:EncryptionContext:aws:kinesis:arn" = local.stream_arn
    }
  }

  reader_policy = local.enabled ? jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [{
        Sid    = "AllowKinesisStreamRead"
        Effect = "Allow"
        Action = [
          "kinesis:GetRecords",
          "kinesis:GetShardIterator",
          "kinesis:DescribeStream",
          "kinesis:DescribeStreamSummary",
          "kinesis:ListShards",
        ]
        Resource = local.stream_arn
      }],
      length(local.consumer_arns) > 0 ? [{
        Sid      = "AllowKinesisEnhancedFanOutRead"
        Effect   = "Allow"
        Action   = ["kinesis:SubscribeToShard", "kinesis:DescribeStreamConsumer"]
        Resource = local.consumer_arns
      }] : [],
      [{
        Sid       = "AllowKinesisStreamKMSRead"
        Effect    = "Allow"
        Action    = ["kms:Decrypt"]
        Resource  = var.kms_key_id
        Condition = local.kms_condition
      }]
    )
  }) : null

  writer_own_statements = [
    {
      Sid      = "AllowKinesisStreamWrite"
      Effect   = "Allow"
      Action   = ["kinesis:PutRecord", "kinesis:PutRecords", "kinesis:DescribeStreamSummary"]
      Resource = local.stream_arn
    },
    {
      Sid       = "AllowKinesisStreamKMSWrite"
      Effect    = "Allow"
      Action    = ["kms:GenerateDataKey"]
      Resource  = var.kms_key_id
      Condition = local.kms_condition
    }
  ]

  # Raw Statement entries from another stream's reader_policy/writer_policy
  # (a full {Version, Statement} document), folded into this stream's own
  # combined_policy below (never into writer_policy - see main.tf's top
  # comment and additional_policy_json's description). Each entry's Sid is
  # rewritten so it can never collide with writer_own_statements' own Sids,
  # or with another folded-in entry's, even when additional_policy_json is
  # itself a writer_policy-shaped document.
  additional_statements = var.additional_policy_json != null ? [
    for i, s in jsondecode(var.additional_policy_json).Statement : merge(s, {
      Sid = "Additional${try(s.Sid, "")}${i}"
    })
  ] : []

  writer_policy = local.enabled ? jsonencode({
    Version   = "2012-10-17"
    Statement = local.writer_own_statements
  }) : null

  combined_policy = local.enabled ? jsonencode({
    Version   = "2012-10-17"
    Statement = concat(local.writer_own_statements, local.additional_statements)
  }) : null
}
