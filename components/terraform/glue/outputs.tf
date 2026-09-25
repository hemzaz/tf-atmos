output "database_name" {
  description = "Glue catalog database name"
  value       = one(aws_glue_catalog_database.this[*].name)
}

output "database_arn" {
  description = "Glue catalog database ARN"
  value       = one(aws_glue_catalog_database.this[*].arn)
}

output "crawler_names" {
  description = "Crawler name per crawlers key"
  value       = { for k, c in aws_glue_crawler.this : k => c.name }
}

output "crawler_arns" {
  description = "Crawler ARN per crawlers key"
  value       = { for k, c in aws_glue_crawler.this : k => c.arn }
}

output "role_arn" {
  description = "ARN of the IAM role every crawler in this instance assumes"
  value       = one(aws_iam_role.crawler[*].arn)
}

output "security_configuration_name" {
  description = "Name of the KMS-encrypted security configuration every crawler in this instance uses"
  value       = one(aws_glue_security_configuration.this[*].name)
}
