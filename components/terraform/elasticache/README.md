# elasticache

Creates an `aws_elasticache_replication_group` (Redis/Valkey) with its subnet
group and a security group. Encryption at rest and in transit are on by
default and validated to stay on; the AUTH token is required whenever transit
encryption is enabled, so the cache is never reachable unauthenticated.
`num_cache_nodes` + `automatic_failover_enabled` + `multi_az_enabled` describe
a replicated cache, so this is a replication group, not an
`aws_elasticache_cluster` — that resource has neither failover nor Multi-AZ.

## Deployed instances

None. The `elasticache:` block in prod's
`stacks/orgs/fnx/prod/eu-west-2/production/components/services.yaml` is a var
of the (`enabled: false`) `infrastructure` component, not an instance of this
root module. Stack rewiring is handled separately.

## Inputs / outputs

| Key | Notes |
|---|---|
| `region`, `tags`, `cluster_id`, `vpc_id`, `subnet_ids` (required) | `tags` must include a non-empty `Environment`; it prefixes every resource name |
| `at_rest_encryption_enabled`, `transit_encryption_enabled` | default `true`; validation forces `true` |
| `auth_token` | sensitive, 16-128 chars, no `/ " @` or spaces; required when transit encryption is on; never exported |
| `num_cache_nodes` (2) | maps to `num_cache_clusters`; `automatic_failover_enabled` requires >= 2, `multi_az_enabled` requires failover |
| `allowed_security_group_ids`, `allowed_cidr_blocks` | ingress on `port` (6379); `0.0.0.0/0` is rejected by validation |
| `kms_key_id` (null), `snapshot_retention_limit` (7), `parameter_group_name` (null) | null KMS key falls back to the AWS-owned key; backups cannot be turned off |
| out: `primary_endpoint_address`, `reader_endpoint_address`, `replication_group_id`/`_arn`, `port`, `security_group_id`, `subnet_group_name` | — |

## Dependencies / gotchas

- Needs a VPC for `vpc_id` and private `subnet_ids`. `vpc/main` exports no
  `elasticache_subnet_ids` today, so prod's `!terraform.state vpc/main
  .elasticache_subnet_ids` will not resolve until vpc adds that output.
- Egress is restricted to node-to-node replication.
- One `#checkov:skip=CKV2_AWS_5`: checkov's graph does not follow
  `aws_security_group.main[0].id` through the `count` index. The identical
  config passes with `count` removed.

## Usage

```
atmos terraform plan elasticache/main -s fnx-prod-production   # after adding an instance
```
