output "replication_group_id" {
  value       = local.enabled ? aws_elasticache_replication_group.main[0].id : null
  description = "ID of the replication group"
}

output "replication_group_arn" {
  value       = local.enabled ? aws_elasticache_replication_group.main[0].arn : null
  description = "ARN of the replication group"
}

output "primary_endpoint_address" {
  value       = local.enabled ? aws_elasticache_replication_group.main[0].primary_endpoint_address : null
  description = "Endpoint clients write to (null in cluster mode; use configuration_endpoint_address)"
}

output "configuration_endpoint_address" {
  value       = local.enabled ? aws_elasticache_replication_group.main[0].configuration_endpoint_address : null
  description = "Endpoint cluster-mode clients connect to (null when cluster mode is off)"
}

output "member_clusters" {
  value       = local.enabled ? sort(aws_elasticache_replication_group.main[0].member_clusters) : []
  description = "Cache cluster (node) IDs in the group: the CacheClusterId dimension of per-node CloudWatch metrics"
}

output "parameter_group_name" {
  value       = local.enabled ? aws_elasticache_replication_group.main[0].parameter_group_name : null
  description = "Parameter group attached to the cache"
}

output "reader_endpoint_address" {
  value       = local.enabled ? aws_elasticache_replication_group.main[0].reader_endpoint_address : null
  description = "Endpoint that load-balances reads across the replicas"
}

output "port" {
  value       = local.enabled ? aws_elasticache_replication_group.main[0].port : null
  description = "Port the cache listens on"
}

output "security_group_id" {
  value       = local.enabled ? aws_security_group.main[0].id : null
  description = "ID of the cache security group; grant application groups access by adding it to allowed_security_group_ids"
}

output "subnet_group_name" {
  value       = local.enabled ? aws_elasticache_subnet_group.main[0].name : null
  description = "Name of the cache subnet group"
}

output "auth_token_secret_arn" {
  value       = local.enabled && var.store_auth_token_in_secrets_manager ? aws_secretsmanager_secret.auth_token[0].arn : null
  description = "ARN of the Secrets Manager secret holding auth_token (JSON key auth_token); null when store_auth_token_in_secrets_manager is false. A consumer (e.g. eks-backend-services) reads it back via an ExternalSecret -- never exported directly, unlike this, the token itself is never in an output"
}
