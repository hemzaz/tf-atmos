# elasticache

A Redis/Valkey `aws_elasticache_replication_group` (failover and Multi-AZ need a replication group,
not `aws_elasticache_cluster`) with subnet group, security group, optional parameter group, and a
Secrets Manager secret holding the AUTH token. Encryption at rest and in transit are forced on. The
AUTH token is generated here, as in Cloud Posse's `aws-elasticache-redis`, but by an ephemeral
`random_password` written through `auth_token_wo` and `secret_string_wo`: it is never in plan,
state or outputs.

## Wiring

- Instance: `elasticache/main` in `fnx-ue1-prod` (a Global Datastore primary), `fnx-ue2-prod` (its
  secondary) and `fnx-ew1-prod` (no Global Datastore); `fnx-ue1-prod`'s and `fnx-ew1-prod`'s
  inherit `elasticache/main-prod` (`stacks/catalog/elasticache/prod.yaml`). Reads `vpc/main .vpc_id` /
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
- The token is sent to the cache when it is created or replaced and when `auth_token_version`
  changes, never otherwise. A cache replacement (a ForceNew change such as `kms_key_id`, or a
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
- The token is not read back from Secrets Manager: the CI plan role has no
  `secretsmanager:GetSecretValue`, and `mock_provider` tests reject any aws ephemeral resource.
- With a rotation Lambda managing the token out of band (the `microservices-platform` template),
  turn off `store_auth_token_in_secrets_manager` and leave `auth_token_version` alone: the
  Lambda's first rotation SETs its own token, and a bump would ROTATE a Terraform one back in.
- Global Datastore (cross-region): `global_replication_group_id_suffix` creates one with this cache
  as its primary (`global_replication_group_id` output); another region's instance joins it as a
  secondary with `global_replication_group_id` (Cloud Posse `aws-elasticache-redis`'s input, which
  has no resource for the primary side). A secondary inherits engine, version, node type,
  encryption and parameter group (those inputs are ignored, as in Cloud Posse), and keeps its own
  subnets, security group, `kms_key_id` (a key in its region) and AUTH token and secret. It is
  read-only until promoted: `aws elasticache failover-global-replication-group`.
- Global Datastore members (extension of Cloud Posse's component, which has no primary side):
  - The global group owns every member's engine version and node type. The primary is a separate
    resource, `aws_elasticache_replication_group.global_primary`, that ignores `engine_version`,
    `node_type` and `parameter_group_name` (the AWS provider's prescribed `ignore_changes`; a
    lifecycle block cannot be conditional). The same `engine_version`/`node_type` inputs feed
    `aws_elasticache_global_replication_group.main`, so a version or size change on the primary's
    stack upgrades or resizes all members through the global group. Switching a cache into or out
    of the primary role replaces it.
  - A major version upgrade also needs the global group's parameter group, which AWS accepts only
    with that upgrade: `aws elasticache modify-global-replication-group --apply-immediately
    --global-replication-group-id <id> --engine-version <v> --cache-parameter-group-name <group>`,
    then set `engine_version`/`family` to match.
  - `auto_minor_version_upgrade` is always false on a member: AWS turns it off on association and
    it cannot be turned back on.
  - The primary role is operated by CLI (`aws elasticache failover-global-replication-group`), not
    by Terraform: the global group ignores `primary_replication_group_id`, which forces a
    replacement and which the provider reads back from the current primary, so a plan after a
    failover leaves the Global Datastore alone.
- `rotation_policy` is a ready-made IAM policy for such a Lambda's `custom_policy`.
- `log_delivery_configuration` (slow-log, engine-log) differs from Cloud Posse's: each entry names
  only its log type and format, and the component creates the log group
  (`/aws/elasticache/<Environment>-<cluster_id>/<log_type>`), always encrypted with `log_kms_key_id`.
