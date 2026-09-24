# awsconfig

The AWS Config recorder for one account and region, modelled on Cloud Posse
[aws-config](https://github.com/cloudposse-terraform-components/aws-config)
with [aws-config-bucket](https://github.com/cloudposse-terraform-components/aws-config-bucket)
folded in. The component is named `awsconfig`, not `aws-config`, because of
the repo's rule against hyphens in component names. It creates:

- a configuration recorder that records every supported resource type,
  including global types (IAM), and a recorder status that starts it;
- a delivery channel to an S3 bucket. The bucket is SSE-KMS with `kms/main`,
  versioned, has all public access blocked and `BucketOwnerEnforced`
  ownership, denies non-TLS requests, and transitions to Glacier before
  expiring. The documented AWS Config bucket statements are limited to this
  account (`aws:SourceAccount`);
- the recorder's IAM role, which uses the AWS managed `AWS_ConfigRole` policy.
  An inline policy lets it write to the bucket under `AWSLogs/<account>/Config/`
  and use the CMK. The role's trust is limited to this account.

Security Hub's FSBP and CIS controls are evaluated by AWS Config rules. Without
a recorder most of them report no data, so `securityhub/defaults` depends on
`awsconfig/main`.

Cloud Posse keeps the bucket in a separate component so an organization can
share one audit-account bucket. Every stack here is its own account, so the
bucket lives with the recorder.

## Deployed instances

`awsconfig/main` in all three stacks (`components/security.yaml`), inheriting
the abstract `awsconfig/defaults` from `stacks/catalog/awsconfig/defaults.yaml`:

```yaml
dependencies:
  components:
    - component: kms/main
vars:
  kms_key_arn: !terraform.state kms/main .key_arn
  include_global_resource_types: true
```

## Inputs / outputs

| Key | Notes |
|---|---|
| `tags` (required) | must contain `Environment` (validated). Used in resource names |
| `kms_key_arn` (required) | `kms/main .key_arn` (validated as a key ARN). Encrypts snapshots and history |
| `name` | default `awsconfig`. The recorder is `<Environment>-<name>` and the bucket `<Environment>-<name>-<account id>` |
| `include_global_resource_types` | default `true`. Turn it on in exactly one region per account (Cloud Posse's `global_resource_collector_region`). Every stack here is one account in one region |
| `recording_frequency` | `CONTINUOUS` (default) or `DAILY` |
| `delivery_frequency` | snapshot delivery, default `TwentyFour_Hours` (validated) |
| `enable_recorder` | default `true` |
| `bucket_glacier_transition_days`, `bucket_expiration_days` | 90 / 365 by default. The transition must come before the expiry (precondition) |
| `force_destroy` | default `false` |
| out: `aws_config_configuration_recorder_id`, `aws_config_iam_role`, `aws_config_delivery_channel_id`, `storage_bucket_id`, `storage_bucket_arn` | Cloud Posse names |

## Dependencies / gotchas

- No key-policy flag is needed on `kms/main`. The recorder delivers with its
  own IAM role, and the key's root-account statement delegates access to IAM.
  The role's inline policy grants `kms:GenerateDataKey`/`kms:Decrypt` on this
  key only.
- An account can have only one recorder per region. If one already exists
  (created outside Terraform), import it or delete it before applying.
- AWS Config bills per configuration item recorded and per rule evaluation.
  `recording_frequency: DAILY` lowers the cost of noisy resource types.
- Checkov skips, with the reason on the resource: the bucket has no access
  logging, cross-region replication or event notifications
  (`CKV_AWS_18/144`, `CKV2_AWS_62`).

## Usage

```
atmos terraform plan awsconfig/main -s fnx-dev-testenv-01
```

Tests: `terraform init -backend=false && terraform test` (real provider with
dummy credentials. Nothing reaches AWS).
