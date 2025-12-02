output "database_id" {
  description = "Glue catalog database ID"
  value       = aws_glue_catalog_database.main.id
}

output "database_name" {
  description = "Glue catalog database name"
  value       = aws_glue_catalog_database.main.name
}

output "database_arn" {
  description = "Glue catalog database ARN"
  value       = aws_glue_catalog_database.main.arn
}

output "table_names" {
  description = "Map of table names"
  value = {
    for k, v in aws_glue_catalog_table.main : k => v.name
  }
}

output "table_arns" {
  description = "Map of table ARNs"
  value = {
    for k, v in aws_glue_catalog_table.main : k => v.arn
  }
}

output "crawler_names" {
  description = "Map of crawler names"
  value = {
    for k, v in aws_glue_crawler.main : k => v.name
  }
}

output "crawler_arns" {
  description = "Map of crawler ARNs"
  value = {
    for k, v in aws_glue_crawler.main : k => v.arn
  }
}

output "crawler_role_arn" {
  description = "Crawler IAM role ARN"
  value       = aws_iam_role.crawler.arn
}

output "schema_registry_arn" {
  description = "Schema registry ARN"
  value       = var.create_schema_registry ? aws_glue_registry.main[0].arn : null
}

output "schema_arns" {
  description = "Map of schema ARNs"
  value = var.create_schema_registry ? {
    for k, v in aws_glue_schema.main : k => v.arn
  } : {}
}

output "data_quality_ruleset_arns" {
  description = "Map of data quality ruleset ARNs"
  value = {
    for k, v in aws_glue_data_quality_ruleset.main : k => v.arn
  }
}
