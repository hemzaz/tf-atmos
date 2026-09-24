# Same outputs as Cloud Posse's aws-dynamodb component.

output "table_name" {
  description = "DynamoDB table name"
  value       = one(aws_dynamodb_table.this[*].name)
}

output "table_id" {
  description = "DynamoDB table ID"
  value       = one(aws_dynamodb_table.this[*].id)
}

output "table_arn" {
  description = "DynamoDB table ARN"
  value       = one(aws_dynamodb_table.this[*].arn)
}

output "global_secondary_index_names" {
  description = "DynamoDB global secondary index names"
  value       = local.enabled ? [for i in var.global_secondary_index_map : i.name] : []
}

output "local_secondary_index_names" {
  description = "DynamoDB local secondary index names"
  value       = local.enabled ? [for i in var.local_secondary_index_map : i.name] : []
}

output "table_stream_arn" {
  description = "DynamoDB table stream ARN (null when streams are off)"
  value       = var.streams_enabled ? one(aws_dynamodb_table.this[*].stream_arn) : null
}

output "table_stream_label" {
  description = "DynamoDB table stream label (null when streams are off)"
  value       = var.streams_enabled ? one(aws_dynamodb_table.this[*].stream_label) : null
}

output "hash_key" {
  description = "DynamoDB table hash key"
  value       = var.hash_key
}

output "range_key" {
  description = "DynamoDB table range key"
  value       = var.range_key
}
