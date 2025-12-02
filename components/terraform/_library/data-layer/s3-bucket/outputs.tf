output "bucket_id" {
  description = "ID of the bucket"
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "ARN of the bucket"
  value       = aws_s3_bucket.this.arn
}

output "bucket_domain_name" {
  description = "Domain name of the bucket"
  value       = aws_s3_bucket.this.bucket_domain_name
}

output "bucket_regional_domain_name" {
  description = "Regional domain name of the bucket"
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "bucket_hosted_zone_id" {
  description = "Route 53 hosted zone ID for the bucket"
  value       = aws_s3_bucket.this.hosted_zone_id
}

output "bucket_region" {
  description = "AWS region of the bucket"
  value       = aws_s3_bucket.this.region
}

output "website_endpoint" {
  description = "Website endpoint (if enabled)"
  value       = var.enable_website ? aws_s3_bucket_website_configuration.this[0].website_endpoint : null
}

output "website_domain" {
  description = "Website domain (if enabled)"
  value       = var.enable_website ? aws_s3_bucket_website_configuration.this[0].website_domain : null
}

output "versioning_enabled" {
  description = "Whether versioning is enabled"
  value       = var.enable_versioning
}

output "encryption_enabled" {
  description = "Whether encryption is enabled"
  value       = var.enable_encryption
}

output "encryption_type" {
  description = "Type of encryption used"
  value       = var.enable_encryption ? var.encryption_type : null
}

output "kms_key_id" {
  description = "KMS key ID used for encryption"
  value       = var.enable_encryption && var.encryption_type != "sse-s3" ? var.kms_key_id : null
  sensitive   = true
}

output "public_access_blocked" {
  description = "Whether public access is blocked"
  value       = var.block_public_access
}

output "lifecycle_rules_count" {
  description = "Number of lifecycle rules configured"
  value       = length(var.lifecycle_rules)
}

output "cors_rules_count" {
  description = "Number of CORS rules configured"
  value       = length(var.cors_rules)
}

output "replication_enabled" {
  description = "Whether replication is enabled"
  value       = var.enable_replication
}

output "object_lock_enabled" {
  description = "Whether object lock is enabled"
  value       = var.enable_object_lock
}

output "intelligent_tiering_enabled" {
  description = "Whether intelligent tiering is enabled"
  value       = var.enable_intelligent_tiering
}

output "logging_enabled" {
  description = "Whether access logging is enabled"
  value       = var.enable_logging
}

output "tags" {
  description = "Tags applied to the bucket"
  value       = local.common_tags
}
