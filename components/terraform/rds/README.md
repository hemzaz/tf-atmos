# rds

Creates an `aws_db_instance` (+ optional read replica), DB subnet group,
security group, parameter group, optional RDS Proxy with its own IAM role,
enhanced-monitoring IAM role, CloudWatch alarms (CPU, connections, free
storage, backup retention), and (in `secrets-rotation.tf`) Secrets Manager password rotation with SNS notifications.

## Deployed instances

Seven: `rds/main` in all three real stacks plus the `fnx-local-localemu`
emulator lane, and `rds/data` in the three real stacks (the old
`infrastructure/*.rds` inputs were remapped here). `rds/main` executes against
LocalEmu on every CI run — the lane that caught the backup/maintenance window
overlap which would have failed `CreateDBInstance` in staging and prod. Floci
cannot run it: no `CreateDBSubnetGroup`.

In all three real stacks, `rds/main`'s `allowed_security_groups` is
`eks/main`'s `eks_cluster_managed_security_group_id` — the consumer is
`eks-backend-services/main`'s pods, which run on `eks/main`'s managed node
groups. Without it, the security group's only ingress rule has an empty
`security_groups` list and nothing can reach the database.

## Inputs / outputs

| Key | Notes |
|---|---|
| `vpc_id`, `subnet_ids`, `identifier`, `engine`, `instance_class` (required) | `vpc_id` must match `^vpc-[a-f0-9]+$` |
| `storage_encrypted` | validation forces `true` always |
| `multi_az`, `deletion_protection`, `publicly_accessible=false`, `backup_retention_period>=7` | forced when `environment = "prod"` |
| `tags` | required; must include a non-empty `Environment` (validated) |
| `monitoring_interval` | one of 0/1/5/10/15/30/60 (validated) |
| out: `instance_endpoint`, `password_secret_arn`, `security_group_id` | — |
| out: `instance_identifier` | The DBInstanceIdentifier CloudWatch dimension (`<Environment>-<identifier>`). Since AWS provider v5, `instance_id` is the DBI resource ID (`db-XXXX...`), not this — `monitoring/*` reads `instance_identifier` for its `rds_instances` dimension input |

## Dependencies / gotchas

- `dependencies.components`: depends on `vpc/main`, which supplies `vpc_id` and the database subnet ids via `!terraform.state`.
- Prod-only hard gates: `multi_az`, `deletion_protection`, `publicly_accessible`, `backup_retention_period` all fail plan/apply if misconfigured when `environment = "prod"`.
- `storage_encrypted` is validated to always be `true` — cannot be disabled.
- `idp-platform` calls this component as a module (`source = "../rds"`), so variable changes here must be mirrored there.

## Usage

```
atmos terraform plan rds/main -s fnx-dev-testenv-01
atmos workflow localemu -f localemu                   # applies + destroys it for real
```
