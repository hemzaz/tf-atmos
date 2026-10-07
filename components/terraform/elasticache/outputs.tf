output "replication_group_id" {
  value       = local.enabled ? local.replication_group.id : null
  description = "ID of the replication group"
}

output "global_replication_group_id" {
  value       = try(aws_elasticache_global_replication_group.main[0].global_replication_group_id, var.global_replication_group_id)
  description = "ID of the Global Datastore this cache belongs to (created here with global_replication_group_id_suffix, or joined with global_replication_group_id); null when it belongs to none. The DR region's secondary reads it"
}

output "replication_group_arn" {
  value       = local.enabled ? local.replication_group.arn : null
  description = "ARN of the replication group"
}

output "primary_endpoint_address" {
  value       = local.enabled ? local.replication_group.primary_endpoint_address : null
  description = "Endpoint clients write to (null in cluster mode; use configuration_endpoint_address)"
}

output "configuration_endpoint_address" {
  value       = local.enabled ? local.replication_group.configuration_endpoint_address : null
  description = "Endpoint cluster-mode clients connect to (null when cluster mode is off)"
}

output "member_clusters" {
  value       = local.enabled ? sort(local.replication_group.member_clusters) : []
  description = "Cache cluster (node) IDs in the group: the CacheClusterId dimension of per-node CloudWatch metrics"
}

output "parameter_group_name" {
  value       = local.enabled ? local.replication_group.parameter_group_name : null
  description = "Parameter group attached to the cache"
}

output "reader_endpoint_address" {
  value       = local.enabled ? local.replication_group.reader_endpoint_address : null
  description = "Endpoint that load-balances reads across the replicas"
}

output "port" {
  value       = local.enabled ? local.replication_group.port : null
  description = "Port the cache listens on"
}

output "security_group_id" {
  value       = local.enabled ? aws_security_group.main[0].id : null
  description = "ID of the cache security group; grant application groups access by adding it to allowed_security_group_ids"
}

output "client_security_group_id" {
  value       = local.enabled ? aws_security_group.client[0].id : null
  description = "Attach this security group to another resource in the same VPC (e.g. a Secrets Manager rotation Lambda's additional_security_group_ids) to grant it access to this cache on port -- without this component ever having to read that resource's own security group back into allowed_security_group_ids, which would create a dependency cycle for a consumer that already reads this component's other outputs (e.g. a rotation Lambda that also reads replication_group_id/configuration_endpoint_address)"
}

output "subnet_group_name" {
  value       = local.enabled ? aws_elasticache_subnet_group.main[0].name : null
  description = "Name of the cache subnet group"
}

output "auth_token_secret_arn" {
  value       = local.store_auth_token ? aws_secretsmanager_secret.auth_token[0].arn : null
  description = "ARN of the Secrets Manager secret holding the generated AUTH token (JSON key auth_token); null when store_auth_token_in_secrets_manager is false. A consumer (e.g. eks-backend-services) reads it via an ExternalSecret. The token itself is never in an output, the plan or the state"
}

output "rotation_policy" {
  value = local.enabled ? jsonencode({
    Version   = "2012-10-17"
    Statement = concat(local.rotation_own_statements, local.rotation_additional_statements)
  }) : null
  description = "A ready-to-use IAM identity policy document (JSON): elasticache:ModifyReplicationGroup and elasticache:DescribeReplicationGroups on this replication group alone, plus, when additional_policy_json is set, that document's Statement entries too (each with its Sid rewritten -- see additional_policy_json's description). Attach it to a Secrets Manager rotation Lambda's execution role via whatever custom/inline policy input that role's own component exposes (e.g. the lambda component's custom_policy). Null when disabled"
}
