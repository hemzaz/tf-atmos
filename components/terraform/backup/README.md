# backup

An AWS Backup vault (optional cross-region replica and vault lock), one plan with daily, weekly and
monthly rules, tag-based and ARN-list selections, a KMS-encrypted SNS topic for job notifications,
failure alarms, a report plan, and an optional scheduled restore-test Lambda. Mirrors Cloud Posse
`aws-backup` (one plan with several rules) on native `aws_backup_*` resources.

## Wiring

- Instance: `backup/main` in the three AWS stacks; reads `kms/main .key_arn` (vault and topic).
- Retention (daily/weekly/monthly days): dev 7/14/30, staging 14/30/90, prod 35/90/2555 with
  monthly cold storage after 90 days. Vault lock and restore testing are off everywhere.
- Prod copies every rule's recovery points to the DR region (`enable_cross_region_backup`,
  `replica_region: us-east-2`): vault `<Environment>-backup-replica` there, on `kms/main`'s
  multi-region replica (`replica_kms_key_arn`, validated to be a key in `replica_region`). The
  copy keeps the source rule's retention and cold storage. `dr-status` reports both vaults.
- Selection is by tag, never `!terraform.state`: backup runs in the same `data` layer as `rds`, and
  `check-deploy-layers.py` rejects same-layer state reads. `rds/main` and `rds/data` carry
  `Backup: "true"`.

## Notes

- Tag selections AND `Backup=true` with `Environment=<env>` through `condition` blocks scoped to one
  resource type. Two `selection_tag` entries would be OR'd and match every RDS instance.
- RDS read replicas are excluded by their `Role=read-replica` tag (BackupSelection ARN patterns only
  allow a trailing wildcard).
- A plan precondition requires `*_retention_days >= *_cold_storage_days + 90` (AWS's minimum);
  cold storage defaults to `null` (off), as in Cloud Posse.
- `enable_vault_lock` makes retention immutable after `vault_lock_changeable_days`; every
  retention must fall within the lock's min and max.
- `kms/main` needs `allow_backup` (on in `kms/defaults`), and the topic has its own publish policy.
- The restore-test Lambda may tag and delete only resources it tagged `BackupRestoreTest=true`, and
  is denied on anything carrying `Environment`, `Backup=true` or the EBS CSI driver's
  `ebs.csi.aws.com/cluster` tag. RDS restore tests are best-effort (Lambda's 15-minute limit).
