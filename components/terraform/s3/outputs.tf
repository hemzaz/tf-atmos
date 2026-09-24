# Cloud Posse's aws-s3-bucket outputs, plus bucket_name.

output "bucket_id" {
  description = "Bucket ID (the bucket name)"
  value       = one(aws_s3_bucket.this[*].id)
}

output "bucket_arn" {
  description = "Bucket ARN"
  value       = one(aws_s3_bucket.this[*].arn)
}

output "bucket_name" {
  description = "Bucket name"
  value       = one(aws_s3_bucket.this[*].bucket)
}

output "bucket_domain_name" {
  description = "Bucket domain name (<bucket>.s3.amazonaws.com)"
  value       = one(aws_s3_bucket.this[*].bucket_domain_name)
}

output "bucket_regional_domain_name" {
  description = "Bucket region-specific domain name (for CloudFront origins)"
  value       = one(aws_s3_bucket.this[*].bucket_regional_domain_name)
}

output "bucket_region" {
  description = "Bucket region"
  value       = one(aws_s3_bucket.this[*].region)
}
