# athena

One Athena workgroup per instance, modelled on Cloud Posse's
[aws-athena](https://github.com/cloudposse-terraform-components/aws-athena)
component (which wraps
[cloudposse/terraform-aws-athena](https://github.com/cloudposse/terraform-aws-athena)).
Written as a plain resource, like this repo's other short-name root
components (`stepfunctions`, `kinesis`, `sns`, `sqs`).

## Deployed instances

`data-pipeline/athena` in `stacks/catalog/templates/data-pipeline.yaml` (a
template, not a deployed stack). The abstract base `athena/defaults`
(`stacks/catalog/athena/defaults.yaml`) wires the key from `kms/main`; the
instance sets `name`, `output_location` (a `data-pipeline/s3-athena-results`
`s3` instance's `bucket_name`, via `!terraform.state`) and `named_queries`,
each reading `data-pipeline/glue-database`'s `database_name`.

## Inputs / outputs

| Key | Notes |
|---|---|
| `region`, `tags`, `name`, `output_location`, `kms_key_arn` (required) | `tags` must include a non-empty `Environment`. The workgroup and each named query are named `<Environment>-<name>[-<named_queries key>]`. `output_location` must be an `s3://` URI (typically `!terraform.state <an s3 instance> .bucket_name`, formatted to `s3://<bucket>/`). `kms_key_arn` must be a full KMS key ARN |
| `description` (`""`) | Workgroup description |
| `enforce_workgroup_configuration` (`true`) | Force every query in the workgroup to use this workgroup's own output location/encryption/cutoff instead of client-supplied ones |
| `publish_cloudwatch_metrics_enabled` (`true`) | Publish workgroup query metrics to CloudWatch |
| `bytes_scanned_cutoff_per_query` (`null`) | Cancel a query once it scans this many bytes; `null` disables the cutoff. Must be `null` or at least `10485760` (10 MB, the AWS minimum) - enforced by a variable validation |
| `engine_version` (`"Athena engine version 3"`) | Passed through as `configuration.engine_version.selected_engine_version` |
| `requester_pays_enabled` (`false`) | Allow queries against requester-pays S3 buckets |
| `force_destroy` (`false`) | Let terraform delete a non-empty workgroup |
| `named_queries` (`{}`) | Map of saved queries, keyed by a short suffix. Each entry: `database` (required, the Glue/Athena database to run against), `query` (required), `description` (optional, `""`) |
| `enabled` (`true`) | `false` creates nothing, including any named queries |
| out: `workgroup_name`, `workgroup_arn` | Always set when enabled |
| out: `named_query_ids` | Map keyed by the `named_queries` key. Empty map when `named_queries = {}` |

## Dependencies / gotchas

- **Result encryption is always `SSE_KMS`** with a customer managed key -
  there is no unencrypted or SSE_S3/CSE_KMS option, unlike upstream (see
  "Differences from Cloud Posse").
- **No dedicated IAM role, and no KMS grant of its own.** Unlike this repo's
  `glue` crawler role or `stepfunctions` execution role, an Athena query
  runs under whichever IAM identity the caller already has (there is no
  fixed Athena service role to attach a grant to). `kms/main`'s key policy
  delegates to the account root, so that identity's own IAM policy is what
  needs `kms:Decrypt`/`kms:GenerateDataKey`/`kms:Encrypt` on `kms_key_arn`
  plus `s3:PutObject` on the results bucket - grants this component has no
  role of its own to carry, so they belong on the querying principal,
  outside this component (unlike `kinesis`'s `reader_policy`/`writer_policy`
  outputs, there is no fixed principal here to build a ready-made policy
  document around in advance).
- **The results bucket is not created here.** It comes from a separate `s3`
  component instance (`data-pipeline/s3-athena-results`), so it gets this
  repo's standard bucket hardening (TLS-only policy, public access block,
  `s3/defaults`' KMS encryption) instead of the bare, `force_destroy = true`
  bucket Cloud Posse's `create_s3_bucket` path creates. `output_location`
  must be built from that instance's `bucket_name` output (see the
  `data-pipeline/athena` instance in `data-pipeline.yaml`), not written as a
  literal bucket name, or the two can drift apart.
- **`named_queries` names are sanitized, not the map value's own
  `name`/`description` text.** Athena's `Name` field for a saved query only
  allows alphanumerics, periods, underscores and hyphens (no spaces); this
  component computes it as `<Environment>-<name>-<key>` rather than
  accepting caller-supplied free text for it, so a query key like
  `daily_summary` is always a valid name. Put a human-readable title in
  `description` instead.

## Differences from Cloud Posse

- Result encryption is mandatory (always `SSE_KMS` with a customer managed
  key); Cloud Posse's module also supports `SSE_S3`/`CSE_KMS` and can
  provision its own KMS key (`create_kms_key`).
- The results bucket is always an external input (`output_location`, from a
  separate `s3` component instance); Cloud Posse's module can instead create
  a bare bucket itself (`create_s3_bucket`).
- No `aws_athena_database`/`aws_athena_data_catalog` resources: this
  component's `named_queries.database` is a plain string (typically a
  `glue` component instance's `database_name` output), whereas upstream's
  `named_queries` looks up `database` as a key into its own internally
  created `aws_athena_database` map and formats `query` with `%s` for its
  name. Cross-database queries and the Glue Data Catalog (the default for
  new databases) make an Athena-managed `aws_athena_database` redundant here.
