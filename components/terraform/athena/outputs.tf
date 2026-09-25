output "workgroup_name" {
  description = "Athena workgroup name"
  value       = one(aws_athena_workgroup.this[*].name)
}

output "workgroup_arn" {
  description = "Athena workgroup ARN"
  value       = one(aws_athena_workgroup.this[*].arn)
}

output "named_query_ids" {
  description = "Named query ID per named_queries key"
  value       = { for k, q in aws_athena_named_query.this : k => q.id }
}
