# kms

One customer-managed KMS key (optionally multi-region with replicas), with alias, rotation, key
policy and grants. Thin wrapper around `../_library/security/kms-multi-region`. Mirrors Cloud
Posse `aws-kms`: the root-account statement delegates administration to IAM, and consumers get key
use through their own IAM policies.

## Wiring

- Instance: `kms/main` in the three AWS stacks and `fnx-local-sandbox` (not `fnx-local-localemu`).
- Depends on `iam/dev` (dev) or `iam/main` (staging, prod), which creates the Auto Scaling
  service-linked role this key policy names.
- Used by (`.key_arn`): `vpc`, `eks`, `eks-addons`, `external-secrets`, `rds`, `elasticache`, `ec2`,
  `secretsmanager`, `backup`, `cloudtrail`, `awsconfig`, `cost-optimization`, `monitoring`,
  `security-monitoring`, and the template-only catalog bases (`athena`, `dynamodb`, `eventbridge`,
  `glue`, `kinesis`, `s3`, `sns`, `sqs`, `stepfunctions`, `waf`).

## Notes

- KMS validates every key-policy principal at `CreateKey`/`PutKeyPolicy`: naming a role that does
  not exist fails with `MalformedPolicyDocumentException`. That is why no stack sets
  `key_administrators`/`key_users`, and why `allow_autoscaling_ebs` needs the iam dependency.
  The sandbox sets `allow_autoscaling_ebs: false`.
- The `allow_*` flags add condition-scoped statements for service principals the root statement
  does not reach (CloudWatch Logs, log delivery, EventBridge, SNS, S3, CloudWatch alarms,
  CloudTrail, Auto Scaling EBS, Backup, CloudFront). `kms/defaults` turns them on, except
  `allow_cloudfront` (kms:Decrypt for any distribution of the account), which a stack with a
  `cloudfront` instance over an SSE-KMS origin bucket sets on its `kms/main`, and
  `allow_log_delivery_s3` (data keys for vended log delivery into a bucket on this key), which a
  stack whose `cloudfront` instance logs to an s3 bucket sets (the `web-application` template's
  requirement). Prefer them over `key_service_users`, which has no conditions.
- The CI apply role gets key use via `iam`'s `ci_apply_kms_key_aliases` (by alias, because
  `iam/ci` applies in the layer before `kms/main`).
- Replicas get their own region-scoped policy; the `key_policy` output is the primary's.
- `rotation_period_in_days` 90-2560, `deletion_window_in_days` 7-30 (validated).
