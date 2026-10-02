output "delivery_stream_arn" {
  description = "Delivery stream ARN (Cloud Posse: kinesis_firehose_stream_arn), for producers' firehose:PutRecord grants and EventBridge/CloudWatch Logs targets. Null when disabled"
  value       = one(aws_kinesis_firehose_delivery_stream.this[*].arn)
}

output "delivery_stream_name" {
  description = "Delivery stream name (<Environment>-<name>; Cloud Posse: kinesis_firehose_stream_name), for the AWS/Firehose DeliveryStreamName metric dimension. Null when disabled"
  value       = one(aws_kinesis_firehose_delivery_stream.this[*].name)
}

output "role_arn" {
  description = "ARN of the delivery role Firehose uses to write to S3 and the log group. Null when disabled"
  value       = one(aws_iam_role.delivery[*].arn)
}

output "source_role_arn" {
  description = "ARN of the source role Firehose uses to read the Kinesis source stream. Null for a direct put stream or when disabled"
  value       = one(aws_iam_role.source[*].arn)
}

output "log_group_name" {
  description = "Name of the delivery error log group (/aws/kinesisfirehose/<Environment>-<name>). Null when disabled"
  value       = one(aws_cloudwatch_log_group.this[*].name)
}
