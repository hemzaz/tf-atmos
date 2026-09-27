# backup

Mirrors [cloudposse-terraform-components/aws-backup](https://github.com/cloudposse-terraform-components/aws-backup)'s
model on top of the native `aws_backup_*` resources: a vault (plus optional
cross-region replica vault and vault lock), one backup plan with a
daily/weekly/monthly rule each (like cloudposse/terraform-aws-backup's
single-plan/multiple-`rules` shape, rather than one plan per cadence),
AND-conditioned tag-based selections for RDS/EC2/EBS (plus ARN-list
selections for RDS/DynamoDB/EFS), an SNS topic for job notifications (with a
publish policy for `backup.amazonaws.com`/`cloudwatch.amazonaws.com`),
CloudWatch alarms on backup/restore failures, a backup report plan, and a
Lambda function (`aws_lambda_function.backup_testing`, source at
`lambda/backup_testing.py`) that runs a scheduled end-to-end restore test via
EventBridge.

## Deployed instances

`backup/main` in every stack: fnx-dev-testenv-01, fnx-staging-staging-01,
fnx-prod-production (each env's `components/security.yaml`). Every instance
inherits the abstract base `backup/defaults` from
`stacks/catalog/backup/defaults.yaml` and sets its own retention days and
`notification_emails`; retention scales with the stage (7/14/30 days in dev,
14/30/90 in staging, 35/90/2555 — a 7-year monthly retention for prod's
pci-sox-gdpr compliance tag — in prod). All three rules (`aws_backup_plan.main`
has one `rule` block per cadence) live on the same plan, and every selection
below attaches to that one plan, so daily/weekly/monthly retention is
reachable for every selected resource, not only the daily rule. Vault lock and
cross-region replication are off in every instance.

Resource selection is entirely tag-based (`enable_rds_backup`,
`enable_ec2_backup`, `enable_ebs_backup`, all on in `backup/defaults`), never
`!terraform.state`: `workflows/deploy-full-stack.yaml` runs `backup` in the
same "data" phase as `rds` and `elasticache`
(`plan-data`/`deploy-data`), and
`workflows/scripts/common/check-deploy-layers.py` rejects an instance that
reads a same-phase instance's state (that phase's plan step runs before any
of its deploy steps apply, so on a first deploy that state does not exist
yet). `rds/main` and `rds/data` set `Backup: "true"` in their own
`services.yaml` `vars.tags` in every stack so `aws_backup_selection.rds_tagged_daily`
picks them up by an `aws_backup_selection.condition` block ANDing
`aws:ResourceTag/Backup = true` with `aws:ResourceTag/Environment = <var.tags.Environment>`,
scoped to an RDS-only ARN pattern (`arn:aws:rds:...:db:*`) — not by two `selection_tag`
entries, which AWS Backup's `ListOfTags` combines with OR (matching either
tag alone, i.e. effectively every RDS instance in the account, since
`Environment` is set on all of them via provider `default_tags`). `enable_ec2_backup`
and `enable_ebs_backup` follow the same AND'd, resource-type-scoped pattern.

## Inputs / outputs

| Key | Notes |
|---|---|
| `tags` (required) | Must contain an `Environment` key (validated) |
| `region` (required) | Must match AWS region regex |
| `kms_key_arn` | Read via `!terraform.state kms/main .key_arn`; encrypts the vault and the notifications SNS topic |
| `enable_rds_backup`, `enable_ec2_backup`, `enable_ebs_backup` | Tag-based selection: an `aws_backup_selection.condition` block ANDing `Backup=true` with `Environment=<var.tags.Environment>`, scoped by `resources` to that resource type's ARN pattern; all on in `backup/defaults` |
| `rds_instances`, `ebs_volume_ids`, `dynamodb_tables`, `efs_file_systems` | ARN-list selections, for resources this component's own stack does not tag (or is in a different deploy phase); independent of the tag-based selections above |
| `enable_vault_lock`, `enable_cross_region_backup` | Off by default and in every real instance |
| `enable_backup_testing` | Off by default in every real instance (spins up and tears down a real EBS volume or RDS instance on a schedule); `backup_testing_resource_type` picks `EBS` or `RDS` (RDS restore-test support is best-effort — see the Lambda's module docstring's "Known limitation" note on Lambda's 15-minute cap vs. realistic RDS restore times) |
| out: `backup_plan_id`, `backup_plan_arn`, `backup_vault_arn`, `backup_role_arn`, `backup_testing_function_arn` | — |

## Dependencies / gotchas

- `dependencies.components: [kms/main]` (declared in `backup/defaults`):
  `kms_key_arn` reads it. `workflows/scripts/common/check-dependencies.py`
  enforces that every `!terraform.state` target is declared.
- `tags` validation fails the plan if `Environment` key is missing.
- `enable_cross_region_backup = true` requires `replica_region` to be set (validated).
- `enable_vault_lock` makes retention limits immutable after `vault_lock_changeable_days` — irreversible once past that window.
- **M11 fix, hardened further (`aws_iam_role_policy.backup_testing_custom`):**
  the restore-test Lambda's own IAM role can `ec2:CreateTags`/`rds:AddTagsToResource`
  only when the request itself sets `BackupRestoreTest=true` (`aws:RequestTag`),
  and can `ec2:DeleteVolume`/`rds:DeleteDBInstance` only on a resource that
  already carries that tag (`aws:ResourceTag`). Beyond that: `rds:AddTagsToResource`/
  `rds:DeleteDBInstance` are further scoped by Resource ARN to the fixed
  `local.restore_test_db_prefix` every RDS restore-test instance is named
  under, `ec2:CreateTags` additionally requires the target volume to carry no
  `Environment` tag yet (every Terraform-managed volume always does, via
  provider `default_tags`; a just-restored volume never does until this
  Lambda tags it), and an explicit `Deny` blocks all four actions outright on
  any resource already carrying an `Environment` or `Backup` tag as a
  backstop. So a bug in `lambda/backup_testing.py` that tags/deletes the wrong
  ARN still cannot reach a real, managed volume or database — not just an
  untagged one. The actual `ec2:CreateVolume`/`rds:RestoreDBInstanceFromDBSnapshot`
  calls happen under the backup service role (`aws_iam_role.backup`, passed
  as `IamRoleArn` to `backup:StartRestoreJob`), which already carries
  `AWSBackupServiceRolePolicyForRestores` — this Lambda's own role is never
  granted those two actions. `backup:*` read/restore/metadata actions are
  scoped to this component's own vault ARN, not `"*"`. Tested in
  `tests/backup.tftest.hcl` (real AWS provider, dummy credentials,
  `command = plan`; the policy is asserted directly since it is `jsonencode()`d
  on the resource, not built via `aws_iam_policy_document`).
- The vault's own SNS topic (`aws_sns_topic.backup_notifications`) is
  encrypted with `kms_key_arn`; `catalog/kms/defaults.yaml` turns on the
  key's `allow_backup` flag so `backup.amazonaws.com` may publish to it. That
  KMS grant alone is not enough for `aws_backup_vault_notifications` to
  deliver events — the topic also needs its own access policy
  (`aws_sns_topic_policy.backup_notifications`) allowing
  `backup.amazonaws.com` (and `cloudwatch.amazonaws.com`, scoped to the two
  backup/restore failure alarm ARNs) to `SNS:Publish`.

## Usage

```
atmos terraform plan backup/main -s fnx-dev-testenv-01
```
