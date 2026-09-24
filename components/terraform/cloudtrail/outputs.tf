# Output names follow Cloud Posse aws-cloudtrail and aws-cloudtrail-bucket.

output "cloudtrail_id" {
  description = "Name of the trail"
  value       = aws_cloudtrail.this.id
}

output "cloudtrail_arn" {
  description = "ARN of the trail"
  value       = aws_cloudtrail.this.arn
}

output "cloudtrail_home_region" {
  description = "Region the trail was created in"
  value       = aws_cloudtrail.this.home_region
}

output "cloudtrail_logs_log_group_arn" {
  description = "ARN of the CloudWatch log group the trail delivers to"
  value       = aws_cloudwatch_log_group.this.arn
}

output "cloudtrail_logs_log_group_name" {
  description = "Name of the CloudWatch log group the trail delivers to (security-monitoring's CIS metric filters read it)"
  value       = aws_cloudwatch_log_group.this.name
}

output "cloudtrail_logs_role_arn" {
  description = "ARN of the role CloudTrail uses to write to the log group"
  value       = aws_iam_role.cloudwatch_logs.arn
}

output "cloudtrail_logs_role_name" {
  description = "Name of the role CloudTrail uses to write to the log group"
  value       = aws_iam_role.cloudwatch_logs.name
}

output "cloudtrail_bucket_id" {
  description = "Name of the S3 bucket the trail delivers log files to"
  value       = aws_s3_bucket.this.id
}

output "cloudtrail_bucket_arn" {
  description = "ARN of the S3 bucket the trail delivers log files to"
  value       = aws_s3_bucket.this.arn
}
