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
| name_prefix, region | is_multi_region + replica_regions, enable_key_rotation/rotation_period_in_days, key_administrators/key_users/key_service_users, allow_cloudwatch_logs/allow_log_delivery/allow_eventbridge/allow_cloudwatch_alarms/allow_cloudtrail/allow_sns/allow_s3/allow_autoscaling_ebs, alias_name/create_alias, key_policy | `key_arn` read via `!terraform.state kms/main .key_arn` by secretsmanager in every stack (`default_kms_key_id`, set in `stacks/catalog/secretsmanager/defaults.yaml`), by eventbridge (`kms_key_arn`, set in `stacks/catalog/eventbridge/defaults.yaml`), by security-monitoring (`kms_key_id`, set in `stacks/catalog/security-monitoring/defaults.yaml`), by `monitoring/main` and `monitoring/data` in every stack (`kms_key_id`, encrypting the alarm SNS topic and log groups — `allow_cloudwatch_alarms` above lets CloudWatch publish to it), by stepfunctions (`kms_key_arn`, set in `stacks/catalog/stepfunctions/defaults.yaml`), by `eks/defaults` (`node_group_ebs_kms_key_id`) in every stack that runs eks, by dev/staging/prod's compute.yaml (`cluster_encryption_config_kms_key_id` on `eks/main` and `eks/data`), by every `vpc/main`/`vpc/services` instance in dev/staging/prod and the sandbox lane's `vpc/main` (`flow_logs_kms_key_arn`, set per instance next to its `dependencies.components` entry — **not** in `vpc/defaults`, since the LocalEmu stack inherits that abstract base but has no `kms/main` of its own), and in prod also by services.yaml (RDS `kms_key_id`, `performance_insights_kms_key_id`) and compute.yaml (EBS/EC2 `kms_key_arn`, `root_volume_kms_key_id`) |

## Dependencies & gotchas

- `kms/main` depends on `iam` in dev, staging and prod (`iam/dev` in dev,
  `iam/main` in staging and prod): `allow_autoscaling_ebs` (below) names the
  Auto Scaling service-linked role directly, and `iam` provisions that role
  (`enable_autoscaling_service_linked_role`, see `../iam/README.md`) so it
  exists before `kms/main`'s first apply. Its own consumers add their own
  dependency on `kms/main`: secretsmanager (via `secretsmanager/defaults`),
  eventbridge (via `eventbridge/defaults`), sqs (via `sqs/defaults`), every
  eks and vpc instance above, and prod's rds and ec2 instances, so `kms/main`
  is applied before them.
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
- **The CloudWatch Logs delivery service is a separate principal from
  `logs.<region>.amazonaws.com`.** `allow_log_delivery` adds `AllowLogDelivery`
  for `delivery.logs.amazonaws.com` (`kms:Decrypt`, scoped by
  `aws:SourceAccount`). This is step 3 of Step Functions' "Encryption at rest"
  doc: without it, a state machine that CMK-encrypts both itself and its
  execution-history log group cannot actually ship logs (`AccessDenied`) even
  though `allow_cloudwatch_logs` already lets the log group itself be
  encrypted. `kms/defaults` turns it on for every stack; stepfunctions is the
  only consumer today.
- Prod's `key_administrators`/`key_users` are hardcoded ARNs
  (`.../role/Admin`, `.../role/production-eks-node-role`) that must already
  exist before apply — the stack comment notes the iam ci/eks-node instances
  are disabled, so this repo's `iam` component does not create those roles.
- `allow_eventbridge` covers four statements: `AllowEventBridge` (bus and
  archive crypto, scoped by `kms:EncryptionContext:aws:events:event-bus:arn`,
  because archive calls carry no `aws:SourceArn`), `AllowEventBridgeDescribeKey`
  (`aws:SourceAccount` only; DescribeKey has no encryption context),
  `AllowEventBridgeSNSTopics` (rules publishing to an SNS topic encrypted with
  this key) and `AllowEventBridgeSQSQueues` (rules delivering to an SQS queue
  encrypted with this key, and buses using one as their dead-letter queue:
  `kms:GenerateDataKey`/`kms:Decrypt`, scoped by `aws:SourceAccount` and
  `aws:SourceArn` = this account's `rule/*` or `event-bus/*` in this region;
  confirm those keys are sent on the first real apply).
- `allow_sns` adds `AllowSNS`: `sns.amazonaws.com` may use
  `kms:Decrypt`/`kms:GenerateDataKey*` to deliver to SQS queues encrypted with
  this key (an sns subscription to an sqs queue), scoped by
  `aws:SourceAccount` and `aws:SourceArn` = this account's topics in this
  region. `kms/defaults` turns it on.
- `allow_s3` adds `AllowS3`: `s3.amazonaws.com` may use
  `kms:Decrypt`/`kms:GenerateDataKey*` to send event notifications to SQS
  queues or SNS topics encrypted with this key, scoped by `aws:SourceAccount`
  = this account and `aws:SourceArn` = an S3 bucket (`arn:aws:s3:::*`; bucket
  ARNs carry no account). `kms/defaults` turns it on.
- `allow_cloudwatch_alarms` adds `AllowCloudWatchAlarmsSNSTopics` for
  `cloudwatch.amazonaws.com`. Both SNS statements allow
  `kms:GenerateDataKey*`/`kms:Decrypt` only with
  `kms:EncryptionContext:aws:sns:topicArn` matching this account's topics in
  this region. The CloudWatch one also requires `aws:SourceAccount`; the
  EventBridge one cannot: SNS documents that `aws:SourceAccount`,
  `aws:SourceArn` and `aws:SourceOrgID` in a KMS policy are not supported for
  EventBridge-to-encrypted topics, and delivery fails with them.
  security-monitoring encrypts its alert topic with this key; without them its
  EventBridge rules and CloudWatch alarms cannot publish. Tested in
  `tests/service_access.tftest.hcl`.
- `allow_cloudtrail` adds `AllowCloudTrailEncryptLogs` (`kms:GenerateDataKey*`,
  `kms:EncryptionContext:aws:cloudtrail:arn` like this account's trails),
  `AllowCloudTrailDecrypt` (`kms:Decrypt`, which AWS requires because the trail
  bucket uses an S3 Bucket Key) and `AllowCloudTrailDescribeKey`, all limited by
  `aws:SourceArn` to this account's trails in this region. cloudtrail/main
  encrypts its log files with this key; `kms/defaults` turns it on.
- `allow_autoscaling_ebs` adds `AllowAutoScalingEBSUsage` (`kms:Encrypt`/
  `Decrypt`/`ReEncrypt*`/`GenerateDataKey*`/`DescribeKey`, scoped by
  `kms:ViaService=ec2.<region>.amazonaws.com` and `kms:CallerAccount`) and
  `AllowAutoScalingEBSGrant` (`kms:CreateGrant`, scoped by
  `kms:GrantIsForAWSResource`) for the EC2 Auto Scaling service-linked role
  (`role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling`),
  named directly as the principal in both statements — AWS's documented
  same-account pattern
  (Example 1, https://docs.aws.amazon.com/autoscaling/ec2/userguide/key-policy-requirements-EBS-encryption.html).
  Every managed node group / ASG that launches instances from a CMK-encrypted
  launch template needs this or new instances fail to launch. `eks/defaults`
  sets `node_group_ebs_kms_key_id` to this key, and `kms/defaults` turns this
  flag on for every stack that runs eks (dev, staging, prod).
  **Avoiding the ordering problem:** that service-linked role is created
  automatically the first time an account uses Auto Scaling, so it may not
  exist yet when `kms/main` first applies, and AWS KMS validates every
  principal named in a key policy at `CreateKey`/`PutKeyPolicy` time — naming
  the role directly fails with `MalformedPolicyDocumentException: ... invalid
  principals` in any account that has never used Auto Scaling. This is
  **not** solved by naming the account root instead: per AWS's key-policy
  documentation, a statement whose principal is the account (its root ARN)
  does not by itself grant any IAM principal access — it only lets the
  account delegate access through IAM identity policies — so narrowing it
  back down with an `aws:PrincipalArn` condition grants nothing, since this
  role's AWS-managed policy is fixed and carries no customer-managed-key
  permissions. Instead, `iam` provisions the role
  (`enable_autoscaling_service_linked_role`, see `../iam/README.md`) and
  `kms/main` declares a `dependencies.components` edge to that stack's iam
  instance (`iam/dev` in dev, `iam/main` in staging and prod) so the role
  exists before `kms/main`'s first apply. The sandbox lane's `kms/main` sets
  `allow_autoscaling_ebs: false` explicitly (overriding `kms/defaults`)
  because nothing in that lane runs Auto Scaling or EKS node groups, so it
  has no `iam` instance and needs none.
- `replica_regions` requires `is_multi_region = true` (validation). Each
  replica gets its own generated policy, not a copy of the primary's: the
  region-specific statements above (`AllowCloudWatchLogs`,
  `AllowEventBridge*`, `AllowCloudTrail*`, `AllowAutoScalingEBS*`) are scoped
  to the replica's own region, never the primary's (`key_policy` output is
  the *primary's* document; a replica's is read from the resource itself,
  `module.kms.aws_kms_replica_key.replicas["<region>"].policy`).
- `rotation_period_in_days` validated 90-2560; `deletion_window_in_days`
  validated 7-30.

## Usage

```
atmos terraform plan kms/main -s fnx-prod-production
```
