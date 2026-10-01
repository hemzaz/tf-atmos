# elasticache

A Redis/Valkey `aws_elasticache_replication_group` (failover and Multi-AZ need a replication group,
not `aws_elasticache_cluster`) with subnet group, security group, optional parameter group, and a
Secrets Manager secret holding the AUTH token. Encryption at rest and in transit are forced on. The
AUTH token is generated here, as in Cloud Posse's `aws-elasticache-redis`, but by an ephemeral
`random_password` written through `auth_token_wo` and `secret_string_wo`: it is never in plan,
state or outputs.

## Wiring

- Instance: `elasticache/main` in `fnx-prod-production` only. Reads `vpc/main .vpc_id` /
  `.private_subnet_ids` and `kms/main .key_arn`, admits `eks/main
  .eks_cluster_managed_security_group_id`.
- Used by: `eks-backend-services` (`.auth_token_secret_arn`, `.primary_endpoint_address`, `.port`),
  `monitoring/main` (`.member_clusters`).

## Notes

- `0.0.0.0/0` is rejected in `allowed_cidr_blocks`. A resource that reads this component's outputs
  (for example a rotation Lambda) attaches `client_security_group_id` instead of being added to
  `allowed_security_group_ids`, which would be a cycle.
- Toggling `cluster_mode_enabled` replaces the cache (no online migration). With cluster mode on, a
  named `parameter_group_name` must itself be cluster-enabled (not validated).
- The token is sent to the cache on every create or replacement, and on an update only when
  `auth_token_version` changes. A cache replacement (a ForceNew change such as `kms_key_id`, or a
  tainted create) re-creates the secret version alongside it (`replace_triggered_by` on the cache
  id), so the two keep agreeing.
- Rotate the token by incrementing `auth_token_version`: the apply sends one new token to both the
  cache and the secret. ROTATE leaves both the old and the new token valid (ElastiCache allows at
  most two). Once consumers have re-read the secret, revoke the old one with SET, which sends the
  new token again:

  ```bash
  aws elasticache modify-replication-group --replication-group-id <Environment>-<cluster_id> \
    --auth-token "$(aws secretsmanager get-secret-value \
      --secret-id redis-auth/<Environment>/<cluster_id> \
      --query SecretString --output text | jq -r .auth_token)" \
    --auth-token-update-strategy SET --apply-immediately
  ```

  Rotating the secret alone desyncs the two.
- A secret version replaced alone or deleted out of band, or an apply that fails between the secret
  and the cache, leaves them disagreeing: bump `auth_token_version` and apply again.
- The token is not read back from Secrets Manager (idp-platform's pattern): the CI plan role has no
  `secretsmanager:GetSecretValue`, and `mock_provider` tests reject any aws ephemeral resource.
- With a rotation Lambda managing the token out of band (the `microservices-platform` template),
  turn off `store_auth_token_in_secrets_manager` and leave `auth_token_version` alone: the
  Lambda's first rotation SETs its own token, and a bump would ROTATE a Terraform one back in.
- `rotation_policy` is a ready-made IAM policy for such a Lambda's `custom_policy`.
