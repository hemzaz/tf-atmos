# backup

Creates an AWS Backup vault (plus optional cross-region replica vault and
vault lock), daily/weekly/monthly backup plans with selections for RDS,
DynamoDB, EFS, EC2 and EBS resources, SNS notifications, CloudWatch alarms on
backup/restore failures, a backup report plan, and a Lambda function
(`aws_lambda_function.backup_testing`) running scheduled restore tests via EventBridge.

## Deployed instances

Not currently deployed in any of the 3 real stacks (fnx-dev-testenv-01,
fnx-staging-staging-01, fnx-prod-production) — zero instances in the stack
maps. A stack must add a `backup` (or `backup/<name>`) entry under
`components.terraform` before this applies.

## Inputs / outputs

| Key | Notes |
|---|---|
| `tags` (required) | Must contain an `Environment` key (validated) |
| `region` (required) | Must match AWS region regex |
| `kms_key_arn` | Optional; vault uses AWS-managed key if unset |
| `enable_vault_lock`, `enable_cross_region_backup` | Off by default |
| `rds_instances`, `dynamodb_tables`, `efs_file_systems` | Resource ARNs to include in daily selections |
| out: `backup_vault_arn`, `backup_role_arn`, `backup_testing_function_arn` | — |

## Dependencies / gotchas

- No `dependencies.components` entries exist anywhere (component is unused).
- `tags` validation fails the plan if `Environment` key is missing.
- `enable_cross_region_backup = true` requires `replica_region` to be set (validated).
- `enable_vault_lock` makes retention limits immutable after `vault_lock_changeable_days` — irreversible once past that window.

## Usage

```
atmos terraform plan backup -s fnx-dev-testenv-01
```
(after adding a `backup` component entry to that stack's catalog/services).
