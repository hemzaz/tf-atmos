# elasticache

Creates an `aws_elasticache_replication_group` (Redis/Valkey) with its subnet
group and a security group. Encryption at rest and in transit are on by
default and validated to stay on; the AUTH token is required whenever transit
encryption is enabled, so the cache is never reachable unauthenticated.
`num_cache_nodes` + `automatic_failover_enabled` + `multi_az_enabled` describe
a replicated cache, so this is a replication group, not an
`aws_elasticache_cluster` — that resource has neither failover nor Multi-AZ.

## Deployed instances

`elasticache/main` in `fnx-prod-production` only
(`stacks/orgs/fnx/prod/eu-west-2/production/components/services.yaml`), the
only stack with a real cache workload today; dev and staging run no instance
(see `stacks/catalog/elasticache/defaults.yaml`). `eks-backend-services/main`
in prod reads `auth_token_secret_arn` below to populate its redis
`ExternalSecret` (its `redis_enabled` flag is off in dev/staging for the same
reason). `allowed_security_group_ids` is `eks/main`'s
`eks_cluster_managed_security_group_id` (`eks-backend-services/main`'s pods
are the consumer), and `auth_token_secret_kms_key_id` is `kms/main`'s
`key_arn` — `external-secrets/main`'s IAM policy already grants `kms:Decrypt`
on that key, gated by `kms:ViaService=secretsmanager`.

## Inputs / outputs

| Key | Notes |
|---|---|
| `region`, `tags`, `cluster_id`, `vpc_id`, `subnet_ids` (required) | `tags` must include a non-empty `Environment`; it prefixes every resource name |
| `at_rest_encryption_enabled`, `transit_encryption_enabled` | default `true`; validation forces `true` |
| `auth_token` | sensitive, 16-128 chars, no `/ " @` or spaces; required when transit encryption is on; never exported directly |
| `store_auth_token_in_secrets_manager` (`true`), `auth_token_secret_kms_key_id` (null), `auth_token_secret_recovery_window_in_days` (30) | mirrors `ec2`'s ssh-key pattern: `auth_token` is also written to a Secrets Manager secret (`redis-auth/<Environment>/<cluster_id>`, JSON key `auth_token`) so a consumer can read it back via an `ExternalSecret` instead of a Terraform variable — `auth_token` itself only ever flows into `aws_elasticache_replication_group` and this secret, never a plain output |
| `num_cache_nodes` (2) | maps to `num_cache_clusters`; `automatic_failover_enabled` requires >= 2, `multi_az_enabled` requires failover |
| `allowed_security_group_ids`, `allowed_cidr_blocks` | ingress on `port` (6379); `0.0.0.0/0` is rejected by validation |
| `kms_key_id` (null), `snapshot_retention_limit` (7) | null KMS key falls back to the AWS-owned key; backups cannot be turned off |
| `cluster_mode_enabled` (false), `cluster_mode_num_node_groups` (1), `cluster_mode_replicas_per_node_group` (1) | Cloud Posse's names. On: shards replace `num_cache_nodes`, failover is required. `0` replicas per shard is allowed, as AWS does, for cheaper dev/test shards with no failover target. **Toggling `cluster_mode_enabled` on an existing cache is not an in-place migration** — this component has no online-migration path between the two topologies (or for flipping `cluster-enabled` on an attached, in-use parameter group), so treat a change as replacing the cache |
| `family` (null), `parameters` ([]), `parameter_group_name` (null) | with `parameters` or cluster mode, a group `<Environment>-<cluster_id>-<family>` (family in the name so a family change, which forces replacement, doesn't collide with the old group under `create_before_destroy`) is created in `family` (required then, and validated to start with `engine`, e.g. `redis6.x`/`redis7`/`redis5.0` for `redis`, `valkey8` for `valkey`) and attached; cluster mode forces `cluster-enabled=yes`. Setting `cluster-enabled` directly in `parameters` is rejected by validation — use `cluster_mode_enabled` instead. `parameter_group_name` attaches an existing group instead and excludes `parameters`; **when `cluster_mode_enabled` is true, that named group must itself be cluster-enabled** (e.g. `default.<family>.cluster.on`) — not validated, only documented |
| out: `primary_endpoint_address` (null in cluster mode), `configuration_endpoint_address` (cluster mode), `reader_endpoint_address`, `replication_group_id`/`_arn`, `member_clusters`, `parameter_group_name`, `port`, `security_group_id`, `subnet_group_name`, `auth_token_secret_arn` | `member_clusters` are the node IDs, the `CacheClusterId` dimension of per-node CloudWatch metrics; `auth_token_secret_arn` is null when `store_auth_token_in_secrets_manager` is false |

## Dependencies / gotchas

- Needs a VPC for `vpc_id` and private `subnet_ids`. `vpc/main` exports no
  `elasticache_subnet_ids` today, so prod's `!terraform.state vpc/main
  .elasticache_subnet_ids` will not resolve until vpc adds that output.
- Egress is restricted to node-to-node replication.
- One `#checkov:skip=CKV2_AWS_5`: checkov's graph does not follow
  `aws_security_group.main[0].id` through the `count` index. The identical
  config passes with `count` removed.
- One `#checkov:skip=CKV2_AWS_57` on `aws_secretsmanager_secret.auth_token`:
  that secret only ever mirrors the replication group's `auth_token` input
  (`!env PROD_ELASTICACHE_AUTH_TOKEN` today); rotating the secret alone, with
  no matching update to `aws_elasticache_replication_group.main`, would
  desync the two. Rotate by changing `auth_token`.

## Tests

`tests/elasticache.tftest.hcl`, run against a mock provider:
`terraform init -backend=false && terraform test`.

## Usage

```
atmos terraform plan elasticache/main -s fnx-prod-production   # after adding an instance
```
