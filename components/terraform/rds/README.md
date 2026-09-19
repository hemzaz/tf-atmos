# rds

Creates an `aws_db_instance` (+ optional read replica), DB subnet group,
security group, parameter group, optional RDS Proxy with its own IAM role,
enhanced-monitoring IAM role, CloudWatch alarms (CPU, connections, free
storage, backup retention), and (in `secrets-rotation.tf`) Secrets Manager password rotation with SNS notifications.

## Deployed instances

Not currently instantiated in any of the 3 real stacks. Every stack
(fnx-dev-testenv-01, fnx-staging-staging-01, fnx-prod-production) only has an
**abstract** catalog entry (`stacks/catalog/infrastructure/defaults.yaml`) —
no real `rds`/`rds/main` instance is deployed today. The `rds:` vars under
`infrastructure/main`/`infrastructure/data` in `services.yaml` are inputs to
the (currently `enabled: false`) `infrastructure` component, not this one. A
working usage pattern (`web-application/rds`) exists only in
`stacks/catalog/templates/web-application.yaml`, which no real stack imports.

## Inputs / outputs

| Key | Notes |
|---|---|
| `vpc_id`, `subnet_ids`, `identifier`, `engine`, `instance_class` (required) | `vpc_id` must match `^vpc-[a-f0-9]+$` |
| `storage_encrypted` | validation forces `true` always |
| `multi_az`, `deletion_protection`, `publicly_accessible=false`, `backup_retention_period>=7` | forced when `environment = "prod"` |
| `monitoring_interval` | one of 0/1/5/10/15/30/60 (validated) |
| out: `instance_endpoint`, `password_secret_arn`, `security_group_id` | — |

## Dependencies / gotchas

- `dependencies.components`: depends on `vpc/main` (from the abstract stanza — never exercised by a real deploy).
- Prod-only hard gates: `multi_az`, `deletion_protection`, `publicly_accessible`, `backup_retention_period` all fail plan/apply if misconfigured when `environment = "prod"`.
- `storage_encrypted` is validated to always be `true` — cannot be disabled.

## Usage

No real instance to plan today. If instantiated (e.g. copying `web-application/rds`):
```
atmos terraform plan rds -s fnx-dev-testenv-01
```
