output "key_arn" {
  description = "ARN of the primary KMS key"
  value       = module.kms.key_arn
}

output "key_id" {
  description = "ID of the primary KMS key"
  value       = module.kms.key_id
}

output "alias_name" {
  description = "Name of the KMS key alias"
  value       = module.kms.key_alias_name
}

output "alias_arn" {
  description = "ARN of the KMS key alias"
  value       = module.kms.key_alias_arn
}

output "replica_keys" {
  description = "Replica keys by region (empty for a single-region key)"
  value       = module.kms.replica_keys
}
