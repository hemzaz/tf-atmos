output "replication_role_arn" {
  description = "ARN of the IAM role for S3 replication"
  value       = aws_iam_role.replication.arn
}

output "replication_role_name" {
  description = "Name of the IAM role for S3 replication"
  value       = aws_iam_role.replication.name
}

output "replication_policy_arn" {
  description = "ARN of the IAM policy for S3 replication"
  value       = aws_iam_policy.replication.arn
}

output "replication_configuration_id" {
  description = "ID of the S3 bucket replication configuration"
  value       = aws_s3_bucket_replication_configuration.this.id
}

output "source_bucket_versioning_status" {
  description = "Versioning status of the source bucket"
  value       = aws_s3_bucket_versioning.source.versioning_configuration[0].status
}

output "destination_bucket_versioning_status" {
  description = "Versioning status of the destination bucket"
  value       = aws_s3_bucket_versioning.destination.versioning_configuration[0].status
}

output "replication_rules" {
  description = "List of replication rule IDs"
  value       = [for rule in var.replication_rules : rule.id]
}

output "replication_metrics" {
  description = "CloudWatch metrics for replication monitoring"
  value = {
    namespace = "AWS/S3"
    metrics = [
      "ReplicationLatency",
      "BytesPendingReplication",
      "OperationsPendingReplication",
      "OperationsFailedReplication"
    ]
    dimensions = {
      SourceBucket      = var.source_bucket_id
      DestinationBucket = var.destination_bucket_id
    }
  }
}
