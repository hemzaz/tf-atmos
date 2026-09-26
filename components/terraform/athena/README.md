# athena

One Athena workgroup per instance, with its saved (named) queries and any
extra data catalogs, modelled on Cloud Posse's
[aws-athena](https://github.com/cloudposse-terraform-components/aws-athena)
component (which wraps
[cloudposse/terraform-aws-athena](https://github.com/cloudposse/terraform-aws-athena)).
Written as plain resources, like this repo's other root components
(`stepfunctions`, `kinesis`, `sns`, `sqs`).

## Deployed instances

`data-pipeline/athena` in `stacks/catalog/templates/data-pipeline.yaml` (a
template; no stack imports it yet). The abstract base `athena/defaults`
(`stacks/catalog/athena/defaults.yaml`) wires the key from `kms/main`; the
instance sets `name`, `output_location` (the `data-pipeline/s3-athena-results`
bucket), `named_queries` against `data-pipeline/glue-database`'s database,
and `query_database_names`/`query_source_buckets` for `query_policy`.
`data-pipeline/step-functions` reads `workgroup_name`.

## Inputs / outputs

| Key | Notes |
|---|---|
| `region`, `tags`, `name`, `output_location`, `kms_key_arn` (required) | `tags` must include a non-empty `Environment`. The workgroup, named queries and data catalogs are named `<Environment>-<name>[-<key>]`. `output_location` must be an `s3://` URI (typically built from an `s3` instance's `bucket_name`). `kms_key_arn` must be a full KMS key ARN |
| `description` (`""`) | Workgroup description |
| `publish_cloudwatch_metrics_enabled` (`true`) | Publish workgroup query metrics to CloudWatch |
| `bytes_scanned_cutoff_per_query` (`null`) | Cancel a query after this many bytes; `null` or at least `10485760` (10 MB) |
| `engine_version` (`"Athena engine version 3"`) | `selected_engine_version` |
| `requester_pays_enabled` (`false`), `force_destroy` (`false`) | Passed through |
| `named_queries` (`{}`) | Map keyed by suffix: `database`, `query` (required), `description` (`""`). The Name is `<Environment>-<name>-<key>` (Athena names allow no spaces) |
| `data_catalogs` (`{}`) | Map keyed by suffix: `type` (`GLUE` - requires `parameters.catalog-id`, a 12-digit account - `LAMBDA`, `HIVE`, `FEDERATED`), `parameters`, `description` (`"Managed by Terraform"`; AWS requires one). The account's own Glue catalog (`AwsDataCatalog`) needs no entry |
| `query_database_names` / `query_source_buckets` (`[]`) | Glue databases and bucket names `query_policy` grants read on |
| `enabled` (`true`) | `false` creates nothing |
| out: `workgroup_name`, `workgroup_arn`, `results_bucket_name` | `null` when disabled |
| out: `named_query_ids`, `data_catalog_names` | Maps keyed by the input keys |
| out: `query_policy` | IAM policy JSON for a principal running queries here: Athena query actions on this workgroup's ARN, list/read/write on the results bucket, KMS on `kms_key_arn`, Glue catalog read on `query_database_names` (catalog, databases, their tables) and S3 read on `query_source_buckets`. No wildcard resources. `null` when disabled |

## Encryption and IAM

- **Results are always `SSE_KMS`** with `kms_key_arn`, and
  `enforce_workgroup_configuration` is always `true` (not an input), so a
  client cannot redirect results or turn encryption off.
  `expected_bucket_owner` is this account.
- **No Athena service role exists**: queries run under the caller's own
  identity. `kms/main`'s key policy delegates to the account root, so that
  identity's IAM policy is what grants key use - `query_policy` is that
  policy, scoped to this workgroup. No key-policy statement is needed.
- **The results bucket is not created here**: it is a separate `s3`
  instance (`data-pipeline/s3-athena-results`) with this repo's standard
  hardening (TLS-only, public access block, `s3/defaults` KMS encryption).

## Differences from Cloud Posse

- Result encryption is mandatory (`SSE_KMS`, customer managed key) and the
  workgroup configuration is always enforced; upstream allows `SSE_S3`/
  `CSE_KMS`, optional enforcement and can create its own key.
- The results bucket is an input (`output_location`); upstream can create a
  bare bucket (`create_s3_bucket`).
- No `aws_athena_database`: databases come from the `glue` component, and
  `named_queries.database` is a plain name rather than a key into an
  Athena-managed database map.
- Adds a ready-made `query_policy` output.

## Tests

`tests/athena.tftest.hcl` (mock provider): naming, SSE_KMS result
encryption and bucket owner, enforced configuration, `query_policy` scoping
(with and without catalog/source grants), data catalogs, input validations,
and `enabled = false`.

```sh
cd components/terraform/athena
terraform init -backend=false && terraform test
```
