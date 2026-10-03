output "distribution_id" {
  description = "Distribution ID (Cloud Posse: cf_id), for cache invalidations and the AWS/CloudFront DistributionId metric dimension. Null when disabled"
  value       = one(aws_cloudfront_distribution.this[*].id)
}

output "distribution_arn" {
  description = "Distribution ARN (Cloud Posse: cf_arn). Null when disabled"
  value       = one(aws_cloudfront_distribution.this[*].arn)
}

output "distribution_domain_name" {
  description = "Distribution domain name, <id>.cloudfront.net (Cloud Posse: cf_domain_name), for alias records made elsewhere. Null when disabled"
  value       = one(aws_cloudfront_distribution.this[*].domain_name)
}

output "distribution_hosted_zone_id" {
  description = "Route 53 zone ID for alias records to the distribution (Cloud Posse: cf_hosted_zone_id). Null when disabled"
  value       = one(aws_cloudfront_distribution.this[*].hosted_zone_id)
}

output "origin_access_control_id" {
  description = "ID of the S3 origin access control (Cloud Posse: cf_access_control_id). Null when disabled or without an S3 origin"
  value       = one(aws_cloudfront_origin_access_control.this[*].id)
}

output "vpc_origin_ids" {
  description = "IDs of the CloudFront VPC origins, by custom_origins origin_id (only origins with vpc_origin). Empty when disabled or without VPC origins"
  value       = { for k, v in aws_cloudfront_vpc_origin.this : k => v.id }
}

output "s3_origin_policy_json" {
  description = "Optional: bucket policy JSON letting this distribution only (AWS:SourceArn) read the origin bucket's objects through OAC, a tightening of the s3 allow_cloudfront_oac_read statement (any distribution of the account) through the origin s3 instance's source_policy_documents, applied after the distribution exists. Null when disabled or without an S3 origin"
  value       = local.s3_origin_policy_json
}
