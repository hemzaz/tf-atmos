output "database_name" {
  description = "Glue catalog database name"
  value       = one(aws_glue_catalog_database.this[*].name)
}

output "database_arn" {
  description = "Glue catalog database ARN"
  value       = one(aws_glue_catalog_database.this[*].arn)
}

output "table_names" {
  description = "Catalog table name per tables key"
  value       = { for k, t in aws_glue_catalog_table.this : k => t.name }
}

output "table_arns" {
  description = "Catalog table ARN per tables key"
  value       = { for k, t in aws_glue_catalog_table.this : k => t.arn }
}

output "crawler_names" {
  description = "Crawler name per crawlers key"
  value       = { for k, c in aws_glue_crawler.this : k => c.name }
}

output "crawler_arns" {
  description = "Crawler ARN per crawlers key"
  value       = { for k, c in aws_glue_crawler.this : k => c.arn }
}

output "job_names" {
  description = "Job name per jobs key"
  value       = { for k, j in aws_glue_job.this : k => j.name }
}

output "job_arns" {
  description = "Job ARN per jobs key"
  value       = { for k, j in aws_glue_job.this : k => j.arn }
}

output "trigger_names" {
  description = "Trigger name per triggers key"
  value       = { for k, t in aws_glue_trigger.this : k => t.name }
}

output "role_arn" {
  description = "ARN of the IAM role every crawler and job in this instance assumes"
  value       = one(aws_iam_role.this[*].arn)
}

output "role_name" {
  description = "Name of the IAM role every crawler and job in this instance assumes"
  value       = one(aws_iam_role.this[*].name)
}

output "security_configuration_name" {
  description = "Name of the KMS-encrypted security configuration every crawler and job in this instance uses"
  value       = one(aws_glue_security_configuration.this[*].name)
}
