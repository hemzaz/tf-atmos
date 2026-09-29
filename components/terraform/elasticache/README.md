# elasticache

A Redis/Valkey `aws_elasticache_replication_group` (failover and Multi-AZ need a replication group,
not `aws_elasticache_cluster`) with subnet group, security group, optional parameter group, and a
Secrets Manager copy of the AUTH token. Encryption at rest and in transit are forced on, and the
AUTH token is required.

## Wiring

- Instance: `elasticache/main` in `fnx-prod-production` only. Reads `vpc/main .vpc_id` /
  `.private_subnet_ids` and `kms/main .key_arn`, admits `eks/main
  .eks_cluster_managed_security_group_id`. `auth_token` comes from `!env PROD_ELASTICACHE_AUTH_TOKEN`.
- Used by: `eks-backend-services` (`.auth_token_secret_arn`, `.primary_endpoint_address`, `.port`),
  `monitoring/main` (`.member_clusters`).

## Notes

- `0.0.0.0/0` is rejected in `allowed_cidr_blocks`. A resource that reads this component's outputs
  (for example a rotation Lambda) attaches `client_security_group_id` instead of being added to
  `allowed_security_group_ids`, which would be a cycle.
- Toggling `cluster_mode_enabled` replaces the cache (no online migration). With cluster mode on, a
  named `parameter_group_name` must itself be cluster-enabled (not validated).
- Rotate the token by changing `auth_token`; rotating the stored secret alone desyncs the two.
- With a rotation Lambda managing the token out of band (the `microservices-platform` template),
  an apply that changes `auth_token`'s value re-adds it and undoes the Lambda's cutover. Turn off
  `store_auth_token_in_secrets_manager` there: the Terraform copy would go stale.
- `rotation_policy` is a ready-made IAM policy for such a Lambda's `custom_policy`.
