# cloudtrail

The account's CloudTrail trail, modelled on Cloud Posse
[aws-cloudtrail](https://github.com/cloudposse-terraform-components/aws-cloudtrail)
with [aws-cloudtrail-bucket](https://github.com/cloudposse-terraform-components/aws-cloudtrail-bucket)
folded in. It creates:

- a multi-region trail with log file validation and global service events,
  encrypted with `kms/main` (CIS AWS Foundations 3.1, 3.2 and 3.7);
- the S3 bucket the trail delivers to. The bucket is SSE-KMS with `kms/main`,
  versioned, has all public access blocked and `BucketOwnerEnforced` ownership,
  denies non-TLS requests, and transitions to Glacier before expiring. Only
  this trail may write, and only under `AWSLogs/<account>/` (`aws:SourceArn`);
- a CloudWatch log group `/aws/cloudtrail/<Environment>-<name>`, encrypted with
  `kms/main`, and the IAM role the trail writes to it with (CIS 3.4). The role's
  trust is limited to this trail (`aws:SourceArn`), and it may write only to
  that log group.

`security-monitoring` puts the CIS metric filters (root account usage,
unauthorized API calls, IAM policy changes, security group changes) and their
alarms on the log group.

Cloud Posse keeps the bucket in a separate component so an organization can
share one audit-account bucket. Every stack here is its own account with its
own trail, so the bucket lives with the trail. The input and output names
follow Cloud Posse's.

## Account model

Each stack is its own AWS account. Stack names are
`<tenant>-<account>-<environment>`, with separate dev, staging and prod
accounts, and `guardduty` and `securityhub` already assume one instance per
account. So each stack runs one multi-region trail (`cloudtrail/main`) with its
own bucket and log group. If two stacks ever share an account, disable
`cloudtrail/main` in all but one of them (`metadata.enabled: false`): a second
multi-region trail duplicates every management event and its cost.

## Deployed instances

`cloudtrail/main` in all three stacks (`components/security.yaml`), inheriting
the abstract `cloudtrail/defaults` from `stacks/catalog/cloudtrail/defaults.yaml`:

```yaml
dependencies:
  components:
    - component: kms/main
vars:
  kms_key_arn: !terraform.state kms/main .key_arn
```

## Inputs / outputs

| Key | Notes |
|---|---|
| `tags` (required) | must contain `Environment` (validated). Used in resource names |
| `kms_key_arn` (required) | `kms/main .key_arn` (validated as a key ARN). Encrypts the log files, the bucket and the log group |
| `name` | default `cloudtrail`. The trail is named `<Environment>-<name>` and the bucket `<Environment>-<name>-<account id>` |
| `is_multi_region_trail`, `include_global_service_events`, `enable_log_file_validation`, `enable_logging` | all `true` by default |
| `cloudwatch_logs_retention_in_days` | default 365 (validated against the periods CloudWatch Logs supports) |
| `bucket_glacier_transition_days`, `bucket_expiration_days` | 90 / 365 by default. The transition must come before the expiry (precondition) |
| `force_destroy` | default `false` |
| out: `cloudtrail_logs_log_group_name` | read by `security-monitoring` (`cloudtrail_log_group_name`) |
| out: `cloudtrail_id`, `cloudtrail_arn`, `cloudtrail_home_region`, `cloudtrail_logs_log_group_arn`, `cloudtrail_logs_role_arn`, `cloudtrail_logs_role_name`, `cloudtrail_bucket_id`, `cloudtrail_bucket_arn` | — |

## Dependencies / gotchas

- The `kms/main` key policy must allow CloudTrail and CloudWatch Logs.
  `kms/defaults` sets `allow_cloudtrail` (`kms:GenerateDataKey*`, scoped by
  `kms:EncryptionContext:aws:cloudtrail:arn` and `aws:SourceArn`, plus
  `kms:Decrypt`, which the bucket's S3 Bucket Key needs) and
  `allow_cloudwatch_logs`. Without them the trail or the log group fails to
  create.
- ARNs are built from names, not read from the resources. The bucket policy
  and the role trust must exist before the trail they are scoped to, and
  building them from names keeps those policy documents known at plan time.
- Deploy it before `security-monitoring`. That component fails its plan while
  `cloudtrail_log_group_name` is null (`require_cloudtrail_route`).
- The trail bills nothing for the first copy of management events. The
  CloudWatch Logs ingestion and the S3 storage are billed.
- Checkov skips, with the reason on each resource: the bucket has no access
  logging, cross-region replication or event notifications
  (`CKV_AWS_18/144`, `CKV2_AWS_62`), and the trail has no per-file SNS topic
  (`CKV_AWS_252`).

## Usage

```
atmos terraform plan cloudtrail/main -s fnx-dev-testenv-01
```

Tests: `terraform init -backend=false && terraform test` (real provider with
dummy credentials. Nothing reaches AWS).
