# kms

Thin wrapper around `../_library/security/kms-multi-region`: creates a
single customer-managed KMS key (or a multi-region key with replicas when
`is_multi_region`/`replica_regions` are set) with configurable rotation,
deletion window, key policy/administrators/users/service-users, alias, and
grants.

## Deployed

`kms/main` in every stack: fnx-dev-testenv-01, fnx-staging-staging-01,
fnx-prod-production (each env's `components/security.yaml`) and the standalone
fnx-local-sandbox stack (`stacks/orgs/fnx/local/eu-west-2/sandbox.yaml`). Every
instance inherits the abstract base `kms/defaults` from
`stacks/catalog/kms/defaults.yaml` and sets its own `alias_name`,
`description` and `deletion_window_in_days`. The fnx-local-localemu stack does
not define a `kms/main`: nothing it runs (rds's `kms_key_id`) requires a CMK.

| Inputs (required) | Inputs (behavior) | Outputs consumed |
|---|---|---|
| name_prefix, region | is_multi_region + replica_regions, enable_key_rotation/rotation_period_in_days, key_administrators/key_users/key_service_users, allow_cloudwatch_logs/allow_eventbridge/allow_cloudwatch_alarms/allow_cloudtrail, alias_name/create_alias, key_policy | `key_arn` read via `!terraform.state kms/main .key_arn` by secretsmanager in every stack (`default_kms_key_id`, set in `stacks/catalog/secretsmanager/defaults.yaml`), by eventbridge (`kms_key_arn`, set in `stacks/catalog/eventbridge/defaults.yaml`), by security-monitoring (`kms_key_id`, set in `stacks/catalog/security-monitoring/defaults.yaml`), and in prod also by services.yaml (RDS `kms_key_id`, `performance_insights_kms_key_id`) and compute.yaml (EBS/EC2 `kms_key_arn`, `root_volume_kms_key_id`) |

## Dependencies & gotchas

- `kms/main` declares no `dependencies.components` of its own. Its consumers
  do: secretsmanager (via `secretsmanager/defaults`), eventbridge (via
  `eventbridge/defaults`) and prod's rds, eks and ec2 instances list
  `kms/main`, so it is applied before them.
- The base sets `enable_default_policy: true` and no named
  `key_administrators`: the root-account statement delegates administration
  to IAM, as Cloud Posse's aws-kms does. Only prod adds named ARNs.
- **CloudWatch Logs and EventBridge are service principals**, which the
  root-account statement does not reach. `allow_cloudwatch_logs` and
  `allow_eventbridge` add condition-scoped statements for them
  (`kms:EncryptionContext:aws:logs:arn` for logs;
  `kms:EncryptionContext:aws:events:event-bus:arn` and `aws:SourceAccount` for
  events, both limited to this account and region) — `kms/defaults` turns both on for every stack. Prefer these
  over the generic `key_service_users`, which grants the same actions to a
  service principal with no condition at all.
- Prod's `key_administrators`/`key_users` are hardcoded ARNs
  (`.../role/Admin`, `.../role/production-eks-node-role`) that must already
  exist before apply — the stack comment notes the iam ci/eks-node instances
  are disabled, so this repo's `iam` component does not create those roles.
- `allow_eventbridge` covers three statements: `AllowEventBridge` (bus and
  archive crypto, scoped by `kms:EncryptionContext:aws:events:event-bus:arn`,
  because archive calls carry no `aws:SourceArn`), `AllowEventBridgeDescribeKey`
  (`aws:SourceAccount` only; DescribeKey has no encryption context) and
  `AllowEventBridgeSNSTopics` (rules publishing to an SNS topic encrypted with
  this key).
- `allow_cloudwatch_alarms` adds `AllowCloudWatchAlarmsSNSTopics` for
  `cloudwatch.amazonaws.com`. Both SNS statements allow
  `kms:GenerateDataKey*`/`kms:Decrypt` only with
  `kms:EncryptionContext:aws:sns:topicArn` matching this account's topics in
  this region. The CloudWatch one also requires `aws:SourceAccount`; the
  EventBridge one cannot: SNS documents that `aws:SourceAccount`,
  `aws:SourceArn` and `aws:SourceOrgID` in a KMS policy are not supported for
  EventBridge-to-encrypted topics, and delivery fails with them. security-monitoring encrypts its alert
  topic with this key; without them its EventBridge rules and CloudWatch
  alarms cannot publish. Tested in `tests/service_access.tftest.hcl`.
- `allow_cloudtrail` adds `AllowCloudTrailEncryptLogs` (`kms:GenerateDataKey*`,
  `kms:EncryptionContext:aws:cloudtrail:arn` like this account's trails),
  `AllowCloudTrailDecrypt` (`kms:Decrypt`, which AWS requires because the trail
  bucket uses an S3 Bucket Key) and `AllowCloudTrailDescribeKey`, all limited
  by `aws:SourceArn` to this account's trails in this region. cloudtrail/main encrypts its log files with
  this key; `kms/defaults` turns it on.
- `replica_regions` requires `is_multi_region = true` (validation).
- `rotation_period_in_days` validated 90-2560; `deletion_window_in_days`
  validated 7-30.

## Usage

```
atmos terraform plan kms/main -s fnx-prod-production
```
