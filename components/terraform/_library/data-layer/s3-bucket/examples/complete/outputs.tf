output "bucket_id" {
  description = "ID of the bucket"
  value       = module.s3_bucket.bucket_id
}

output "bucket_arn" {
  description = "ARN of the bucket"
  value       = module.s3_bucket.bucket_arn
}

output "bucket_domain_name" {
  description = "Domain name of the bucket"
  value       = module.s3_bucket.bucket_domain_name
}
