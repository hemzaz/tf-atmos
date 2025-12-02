##############################################
# Key Outputs
##############################################

output "key_id" {
  description = "KMS key ID"
  value       = aws_kms_key.main.id
}

output "key_arn" {
  description = "KMS key ARN"
  value       = aws_kms_key.main.arn
}

output "key_alias_name" {
  description = "KMS key alias name"
  value       = var.create_alias ? aws_kms_alias.main[0].name : ""
}

output "key_alias_arn" {
  description = "KMS key alias ARN"
  value       = var.create_alias ? aws_kms_alias.main[0].arn : ""
}

##############################################
# Replica Keys
##############################################

output "replica_keys" {
  description = "Map of replica region to replica key details"
  value = {
    for region, key in aws_kms_replica_key.replicas : region => {
      key_id  = key.id
      key_arn = key.arn
    }
  }
}

output "replica_count" {
  description = "Number of replica keys created"
  value       = length(aws_kms_replica_key.replicas)
}

##############################################
# Configuration
##############################################

output "key_rotation_enabled" {
  description = "Whether key rotation is enabled"
  value       = aws_kms_key.main.enable_key_rotation
}

output "is_multi_region" {
  description = "Whether this is a multi-region key"
  value       = aws_kms_key.main.multi_region
}

output "grants" {
  description = "Map of grants created"
  value = {
    for name, grant in aws_kms_grant.grants : name => {
      grant_id   = grant.grant_id
      grant_token = grant.grant_token
    }
  }
  sensitive = true
}
