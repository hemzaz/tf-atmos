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

Retention days (`delete_after`) by cadence, and the monthly cadence's cold
storage days (`cold_storage_after`):

| Stage   | daily | weekly | monthly | monthly cold storage |
|---------|-------|--------|---------|-----------------------|
| dev     | 7     | 14     | 30      | off (`null`)          |
| staging | 14    | 30     | 90      | off (`null`)          |
| prod    | 35    | 90     | 2555    | 90                    |

AWS Backup requires `delete_after >= cold_storage_after + 90` (a recovery
point must sit in cold storage at least 90 days before it can be deleted).
`daily_cold_storage_days`/`weekly_cold_storage_days`/`monthly_cold_storage_days`
all default to `null` (off) in `variables.tf`, matching
[cloudposse/terraform-aws-backup](https://github.com/cloudposse/terraform-aws-backup)'s
model (`rules[].lifecycle.cold_storage_after` is unset unless a caller opts
in) -- a fixed non-null default would only be valid for a retention long
enough to satisfy the 90-day rule, and that is each instance's call, not
this component's. `backup/defaults` also sets `monthly_cold_storage_days:
null` explicitly to document the intent. Only the prod instance turns cold
storage back on (`monthly_cold_storage_days: 90`), alongside its long
2555-day monthly retention. `aws_backup_plan.main` also carries a
`lifecycle.precondition` per cadence enforcing this relationship, so a stack
that gets it wrong fails at `terraform plan`, not at `apply`. Daily and
weekly cold storage stay off (`null`) in every instance; no stage's
daily/weekly retention is long enough to turn them on.

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
| `daily_retention_days` (default `7`), `weekly_retention_days` (default `30`), `monthly_retention_days` (default `365`) | `delete_after` per cadence; each must be a whole number of days from 1 to 36500 and satisfy `>= corresponding *_cold_storage_days + 90`, enforced by a precondition on `aws_backup_plan.main` |
| `daily_cold_storage_days`, `weekly_cold_storage_days`, `monthly_cold_storage_days` | Default `null` (no cold storage transition), matching [cloudposse/terraform-aws-backup](https://github.com/cloudposse/terraform-aws-backup)'s `rules[].lifecycle.cold_storage_after`; when set, must satisfy `*_retention_days >= value + 90`, enforced by the same precondition |
| `enable_vault_lock`, `enable_cross_region_backup` | Off by default and in every real instance |
| `vault_lock_changeable_days` (default `3`), `vault_lock_min_retention_days` (default `7`), `vault_lock_max_retention_days` (default `365`) | Non-null whole numbers up to 36500 (the AWS maximum); `changeable_days >= 3` (the AWS minimum), `min >= 1` and `max >= min`. With `enable_vault_lock`, a precondition on `aws_backup_vault_lock_configuration.main` requires every `*_retention_days` to fall within `[min, max]`: a locked vault rejects jobs outside that range |
| `enable_backup_testing` | Off by default in every real instance (spins up and tears down a real EBS volume or RDS instance on a schedule); `backup_testing_resource_type` picks `EBS` or `RDS` (RDS restore-test support is best-effort — see the Lambda's module docstring's "Known limitation" note on Lambda's 15-minute cap vs. realistic RDS restore times) |
| `log_retention_days` (default `365`) | CloudWatch Logs retention for the restore-test Lambda's log group; Checkov (CKV_AWS_338) requires at least 365 days for KMS-encrypted log groups |
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
  already carries that tag (`aws:ResourceTag`). Beyond that: `ec2:CreateTags`/
  `ec2:DeleteVolume` are ARN-scoped to `arn:...:volume/*` and
  `rds:AddTagsToResource`/`rds:DeleteDBInstance` are ARN-scoped to the fixed
  `local.restore_test_db_prefix` every RDS restore-test instance is named
  under; `ec2:CreateTags` additionally requires the target volume to carry no
  `Environment` tag yet (every Terraform-managed volume in this repo carries
  one, via provider `default_tags`; a just-restored volume never does either —
  `StartRestoreJob` only copies a recovery point's tags onto the restored
  resource when the caller passes `CopySourceTagsToRestoredResource=True`,
  which this Lambda never does). That `Environment`-tag check alone is **not**
  sufficient, though: every EBS volume the `eks-addons` `aws-ebs-csi-driver`
  addon provisions for a Kubernetes `PersistentVolume` also carries no
  `Environment` tag — the CSI driver creates volumes via its own AWS API
  calls, not this repo's Terraform, so `default_tags` never reaches them —
  and those are real, in-use application data, not just untagged. So three
  explicit `Deny` statements (not two) block all four actions outright on any
  resource already carrying an `Environment` tag, already carrying a
  `Backup=true` tag, or carrying the `ebs.csi.aws.com/cluster` tag the AWS EBS
  CSI driver adds unconditionally, by default, to every volume and snapshot
  it manages (upstream `kubernetes-sigs/aws-ebs-csi-driver` `docs/tagging.md`,
  "Default Cluster Tag") — a backstop over the EC2 and RDS grants that holds
  for Kubernetes-managed volumes too, not only Terraform-managed ones. So a
  bug in `lambda/backup_testing.py` that tags/deletes the wrong ARN still
  cannot reach a real, managed volume or database, whether it's a
  Terraform-managed resource or a Kubernetes `PersistentVolume`'s backing
  volume — not just an untagged one. The actual `ec2:CreateVolume`/`rds:RestoreDBInstanceFromDBSnapshot`
  calls happen under the backup service role (`aws_iam_role.backup`, passed
  as `IamRoleArn` to `backup:StartRestoreJob`), which already carries
  `AWSBackupServiceRolePolicyForRestores` — this Lambda's own role is never
  granted those two actions. The `backup:*` read/restore/metadata actions are
  split across three statements to match what each one actually authorizes
  against (per the AWS Backup IAM Service Authorization reference):
  `backup:ListRecoveryPointsByBackupVault` is scoped to this component's own
  vault ARN; `backup:StartRestoreJob`/`backup:GetRecoveryPointRestoreMetadata`
  authorize against the recoveryPoint resource type (the underlying EC2/RDS
  snapshot ARN, not the vault), so they are scoped to those resource-type
  patterns instead, further narrowed by an `aws:ResourceTag/Environment`
  condition matching this component's own recovery points; and
  `backup:DescribeRestoreJob` has no resource type at all and must be
  `Resource "*"`. Scoping all four to the vault ARN (as an earlier version of
  this policy did) made `StartRestoreJob`/`GetRecoveryPointRestoreMetadata`
  `AccessDenied` at runtime, so the restore test never actually ran. Tested in
  `tests/backup.tftest.hcl` (real AWS provider, dummy credentials,
  `command = plan`; the policy is asserted directly since it is `jsonencode()`d
  on the resource, not built via `aws_iam_policy_document`).
- **LOW fix — restore-test Lambda log group:** `aws_lambda_function.backup_testing`
  has its own `aws_cloudwatch_log_group.backup_testing`
  (`/aws/lambda/<name>-testing`), encrypted with `kms_key_arn` and retained
  for `log_retention_days` (default 365) — Lambda's own auto-created log
  group has no retention and no CMK encryption, against this repo's
  encrypt-at-rest convention. `catalog/kms/defaults.yaml`'s
  `allow_cloudwatch_logs` already grants `logs.<region>.amazonaws.com` on
  `kms/main`, so no new KMS grant was needed.
- **MEDIUM fix (`aws_backup_selection.rds_tagged_daily`), corrected in
  round-3:** a `string_not_equals` condition on `aws:ResourceTag/Role` =
  `read-replica` (ANDed with the existing `Backup=true`/`Environment=<env>`
  conditions) excludes RDS read replicas from the tag-based RDS selection.
  `rds/main`/`rds/data`'s `Backup=true` tag reaches a `create_read_replica =
  true` instance's read replica too (same `var.tags`), and AWS Backup's
  handling of RDS read replicas is restricted — without the exclusion the
  replica would either duplicate the primary's snapshots or fail its own
  backup job and fire the `NumberOfBackupJobsFailed` alarm. The initial fix
  used `not_resources` with a leading-wildcard ARN pattern
  (`*-read-replica`), but the BackupSelection API only supports a wildcard at
  the end of an ARN pattern (a prefix match), so that pattern would not
  work. `rds/main.tf`'s `aws_db_instance.read_replica` already tags itself
  `Role = "read-replica"`, so excluding by that tag avoids ARN wildcards
  entirely.
- The vault's own SNS topic (`aws_sns_topic.backup_notifications`) is
  encrypted with `kms_key_arn`; `catalog/kms/defaults.yaml` turns on the
  key's `allow_backup` flag so `backup.amazonaws.com` may publish to it. That
  KMS grant alone is not enough for `aws_backup_vault_notifications` to
  deliver events — the topic also needs its own access policy
  (`aws_sns_topic_policy.backup_notifications`) allowing
  `backup.amazonaws.com` (and `cloudwatch.amazonaws.com`, scoped to the two
  backup/restore failure alarm ARNs) to `SNS:Publish`.
- **RDS restore-test metadata overrides:** `lambda/backup_testing.py`'s RDS
  branch of `_restore_metadata` seeds its `Metadata` from the source
  instance's own restore metadata (`backup:GetRecoveryPointRestoreMetadata`),
  then explicitly overrides `DeletionProtection` and `MultiAZ` to `"false"`
  alongside `DBInstanceIdentifier` — a prod source instance's
  `deletion_protection = true` (`stacks/catalog/rds/prod.yaml`) would
  otherwise carry onto this short-lived test instance and make
  `_delete_restored_resource` fail, and Multi-AZ would needlessly double its
  cost for an instance that only exists long enough to validate the restore.

## Usage

```
atmos terraform plan backup/main -s fnx-dev-testenv-01
```
