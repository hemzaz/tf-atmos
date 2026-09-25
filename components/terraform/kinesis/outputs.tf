output "stream_arn" {
  description = "Stream ARN"
  value       = one(aws_kinesis_stream.this[*].arn)
}

output "stream_name" {
  description = "Stream name"
  value       = one(aws_kinesis_stream.this[*].name)
}

output "stream_id" {
  description = "Stream unique identifier"
  value       = one(aws_kinesis_stream.this[*].id)
}

output "consumer_arns" {
  description = "Map of enhanced fan-out consumer name to its ARN, for enabled entries in var.consumers"
  value       = { for k, v in aws_kinesis_stream_consumer.this : k => v.arn }
}

output "reader_policy" {
  description = "A ready-to-use IAM identity policy document (JSON) for a stream reader: the Kinesis actions needed to read the stream (GetRecords, GetShardIterator, DescribeStream, DescribeStreamSummary, ListShards; plus SubscribeToShard and DescribeStreamConsumer on any enhanced fan-out consumer ARNs when consumers is non-empty), and kms:Decrypt on kms_key_id scoped (via kms:ViaService and the aws:kinesis:arn encryption context) to this stream alone - the same grant AWS's own docs show for a Kinesis reader (e.g. Firehose reading an encrypted source stream). (ListStreams is deliberately omitted: it supports no resource-level permissions, so scoping it to this stream's ARN would never actually grant it.) Attach it to a reader's execution role via whatever custom/inline policy input that role's own component exposes (e.g. the lambda component's custom_policy). Null when disabled"
  value       = local.reader_policy
}

output "writer_policy" {
  description = "A ready-to-use IAM identity policy document (JSON) for a stream writer: kinesis:PutRecord, PutRecords and DescribeStreamSummary on the stream, and kms:GenerateDataKey on kms_key_id scoped (via kms:ViaService and the aws:kinesis:arn encryption context) to this stream alone - a KMS-encrypted stream's producer needs to generate a data key to encrypt each record it writes. Always exactly these two statements, regardless of additional_policy_json - see combined_policy for a version that also carries another stream's grants. Attach it to a writer's execution role via whatever custom/inline policy input that role's own component exposes (e.g. the lambda component's custom_policy). Null when disabled"
  value       = local.writer_policy
}

output "combined_policy" {
  description = "writer_policy's own two statements plus, when additional_policy_json is set, that document's Statement entries too (each with its Sid rewritten - prefixed 'Additional' - so it can never collide with writer_policy's own Sids or with another folded-in entry's; see additional_policy_json's description). Use this instead of writer_policy for a consumer that both writes this stream and needs another stream's grants folded in (e.g. via another kinesis instance's reader_policy/writer_policy output as additional_policy_json); use writer_policy itself when only this stream's own write grant is wanted, since writer_policy is guaranteed to never carry more than that. Null when disabled"
  value       = local.combined_policy
}
