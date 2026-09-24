# Output names follow Cloud Posse aws-config and aws-config-bucket.

output "aws_config_configuration_recorder_id" {
  description = "Name of the AWS Config configuration recorder"
  value       = aws_config_configuration_recorder.this.id
}

output "aws_config_iam_role" {
  description = "ARN of the IAM role the recorder uses"
  value       = aws_iam_role.this.arn
}

output "aws_config_delivery_channel_id" {
  description = "Name of the AWS Config delivery channel"
  value       = aws_config_delivery_channel.this.id
}

output "storage_bucket_id" {
  description = "Name of the S3 bucket configuration snapshots and history are delivered to"
  value       = aws_s3_bucket.this.id
}

output "storage_bucket_arn" {
  description = "ARN of the S3 bucket configuration snapshots and history are delivered to"
  value       = aws_s3_bucket.this.arn
}
