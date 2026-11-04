output "cloudtrail_bucket_domain_name" {
  value       = try(module.cloudtrail_s3_bucket.bucket_domain_name, null)
  description = "CloudTrail S3 bucket domain name"
}

output "cloudtrail_bucket_id" {
  value       = try(module.cloudtrail_s3_bucket.bucket_id, null)
  description = "CloudTrail S3 bucket ID"
}

output "cloudtrail_bucket_arn" {
  value       = try(module.cloudtrail_s3_bucket.bucket_arn, null)
  description = "CloudTrail S3 bucket ARN"
}
