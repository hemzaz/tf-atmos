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

output "reader_kms_policy" {
  description = "A ready-to-use IAM identity policy document (JSON), granting kms:Decrypt on kms_key_id scoped (via kms:ViaService and the aws:kinesis:arn encryption context) to this stream alone - the same grant AWS's own docs show for a Kinesis reader (e.g. Firehose reading an encrypted source stream). Attach it to a reader's execution role via whatever custom/inline policy input that role's own component exposes (e.g. the lambda component's custom_policy). Null when disabled"
  value       = local.reader_kms_policy
}
