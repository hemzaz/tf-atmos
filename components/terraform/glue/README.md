# glue

One Glue catalog database and everything that populates and processes it
per instance: catalog tables, crawlers, Spark ETL jobs, triggers, the IAM
role they share, a KMS security configuration and, optionally, the account's
Data Catalog encryption settings.

Modelled on Cloud Posse's Glue components -
[aws-glue-catalog-database](https://github.com/cloudposse-terraform-components/aws-glue-catalog-database),
[aws-glue-catalog-table](https://github.com/cloudposse-terraform-components/aws-glue-catalog-table),
[aws-glue-crawler](https://github.com/cloudposse-terraform-components/aws-glue-crawler),
[aws-glue-job](https://github.com/cloudposse-terraform-components/aws-glue-job),
[aws-glue-trigger](https://github.com/cloudposse-terraform-components/aws-glue-trigger) and
[aws-glue-iam](https://github.com/cloudposse-terraform-components/aws-glue-iam),
which wrap the matching submodules of
[cloudposse/terraform-aws-glue](https://github.com/cloudposse/terraform-aws-glue) -
folded into ONE component (an owner decision for this repo) and written as
plain resources, like this repo's other root components (`stepfunctions`,
`kinesis`, `sns`, `sqs`).

## Deployed instances

`data-pipeline/glue-database` in `stacks/catalog/templates/data-pipeline.yaml`
(a template; no stack imports it yet). The abstract base `glue/defaults`
(`stacks/catalog/glue/defaults.yaml`) wires the key from `kms/main`. The
instance defines:

- tables `raw_events` (Parquet written by `firehose-raw`, partition
  projection on year/month/day/hour), `processed_events` (Parquet written
  by `firehose-processed` - the streaming path and the one canonical
  processed source) and `processed_events_batch` (same schema and
  source/year/month/day partitioning, under `s3-processed/batch/`, written
  only by the transformation job - the reprocessing/backfill path, kept
  apart so no event is counted twice);
- crawlers `processed_data` (catalog target on `processed_events`, adds the
  partitions Firehose writes) and `curated_data` (S3 target on the curated
  bucket). Catalog-target crawlers use `update_behavior = "LOG"`: the tables
  are Terraform-owned, so a crawler that rewrote them would drift against
  every plan. `raw_events` has no crawler - Athena ignores catalog
  partitions on a partition-projection table;
- jobs `transformation` (raw -> `processed_events_batch`, registering
  partitions through a catalog-updating sink) and `curation`
  (`processed_events` -> curated daily summary, de-duplicated on
  `event_id` against Firehose's at-least-once delivery), run by
  `data-pipeline/step-functions`' daily ETL. Both process **the previous
  UTC day** of the run's `--date` (a 02:00 UTC run processes all 24 hours of
  yesterday); an optional `--process_date YYYY-MM-DD` is used as-is instead,
  for backfills. Both are idempotent: `transformation` purges the day's
  output partitions before writing, `curation` overwrites its day's
  partition (dynamic partition overwrite);
- trigger `crawl-curated` (crawl the curated bucket when `curation`
  succeeds);
- `enable_data_catalog_encryption: true` (the template's only glue
  instance). This is **account-wide**: every principal that reads the
  catalog in this account and region - Firehose's schema role
  (`firehose_glue_role_arn`), the Step Functions role, Athena users, this
  role - needs `kms:Decrypt` on `kms/main`. Without it Firehose's Parquet
  conversion cannot read the table schema and silently routes every record
  to the `errors/` prefix.

Readers: `firehose-raw`/`firehose-processed` (`database_name`,
`table_names`), `athena` (`database_name`), `step-functions` (`job_names`,
`database_name`), `eventbridge` (`crawler_names`).

## Inputs / outputs

| Key | Notes |
|---|---|
| `region`, `tags`, `name`, `kms_key_arn` (required) | `tags` must include a non-empty `Environment`. The role is `<Environment>-<name>-glue`; the security configuration, crawlers, jobs and triggers are `<Environment>-<name>[-<key>]`; the database is the same string with hyphens replaced by underscores. `kms_key_arn` must be a full KMS key ARN |
| `database_description` (`""`), `location_uri` (`""`) | Database description and default `s3://` location |
| `create_table_default_permissions` (`[]`) | `{principal = {data_lake_principal_identifier}, permissions}` blocks. The data-pipeline instance grants `ALL` to `IAM_ALLOWED_PRINCIPALS` (no Lake Formation fine-grained access control) |
| `enable_data_catalog_encryption` (`false`) | Sets the account's Data Catalog encryption: metadata `SSE-KMS` and connection password encryption, both with `kms_key_arn`. **One setting per account and region** - enable it on exactly one instance |
| `tables` (`{}`) | Map keyed by table name: `location` (`s3://.../`), `input_format`, `output_format`, `serialization_library` (required), `columns` (required, `{name, type, comment}`), optional `partition_keys`, `parameters`, `ser_de_parameters`, `table_type` (`EXTERNAL_TABLE`), `compressed`, `description`. With `parameters["projection.enabled"] = "true"` and no `storage.location.template`, the component derives `<location><key>=${<key>}/...` from the partition keys |
| `crawlers` (`{}`) | Map keyed by suffix: exactly one of `s3_targets` (`[{path, exclusions}]`) or `catalog_tables` (keys of `tables`; requires `schema_change_policy.delete_behavior = "LOG"`), plus optional `description`, `schedule`, `table_prefix`, `configuration` (map, `jsonencode`d) and `schema_change_policy` |
| `jobs` (`{}`) | Map keyed by suffix: `script` (PySpark source, required) plus optional `description`, `glue_version` (`5.0`), `worker_type` (`G.1X`), `number_of_workers` (`2`), `timeout` (`60`), `max_retries` (`0`), `max_concurrent_runs` (`1`), `job_bookmark_option` (`job-bookmark-enable`), `default_arguments` (merged over the component's `--TempDir`, `--enable-glue-datacatalog`, `--enable-metrics`, `--enable-continuous-cloudwatch-log`, `--job-bookmark-option`, `--catalog_database`) |
| `assets_bucket_name` (`""`) | Required with `jobs`: scripts are uploaded (SSE-KMS) to `scripts/<Environment>-<name>/<key>.py`; `--TempDir` is `temporary/<Environment>-<name>/` |
| `s3_read_buckets` / `s3_write_buckets` (`[]`) | Bucket names (not ARNs) the role may read / write, e.g. job inputs and outputs. Crawler `s3_targets` and table-location buckets are added to the read set automatically |
| `triggers` (`{}`) | Map keyed by suffix: `type` (`SCHEDULED` needs `schedule`, `CONDITIONAL` needs `predicate`, or `ON_DEMAND`), `actions` (`[{job | crawler, arguments, timeout}]`), `predicate` (`{logical = AND|ANY, conditions = [{job | crawler, state}]}`), `enabled`, `start_on_creation`, `description`. Jobs and crawlers are named by their key in this instance; validations reject unknown keys and invalid states |
| `enabled` (`true`) | `false` creates nothing |
| out: `database_name`, `database_arn`, `role_arn`, `role_name`, `security_configuration_name` | `null` when disabled |
| out: `table_names`/`table_arns`, `crawler_names`/`crawler_arns`, `job_names`/`job_arns`, `trigger_names` | Maps keyed by the input keys |

## Encryption and IAM

- **Security configuration** (every crawler and job): CloudWatch Logs
  `SSE-KMS`, job bookmarks `CSE-KMS`, S3 output `SSE-KMS`, all with
  `kms_key_arn`. The encrypted `/aws-glue/*` log groups are covered by
  `kms/main`'s `allow_cloudwatch_logs` key-policy statement (the
  `logs.<region>.amazonaws.com` principal, scoped by
  `kms:EncryptionContext:aws:logs:arn` to this account's log groups); no new
  key-policy statement is needed.
- **Data Catalog encryption** (`enable_data_catalog_encryption`): catalog
  metadata and connection passwords with `kms_key_arn`. Every principal that
  reads the catalog (this role, Athena users, Firehose's schema role) then
  needs `kms:Decrypt` on the key; `kms/main`'s root delegation makes their
  own IAM policies sufficient (this role has it; see `athena`'s
  `query_policy`).
- **Role** (`<Environment>-<name>-glue`, trusted by `glue.amazonaws.com`
  with `aws:SourceAccount`): inline policies only, no AWS managed policy -
  Glue catalog actions on this catalog, database and `table/<db>/*`, plus
  `glue:GetDatabase` alone on `database/default` (Spark's catalog client
  looks it up at session start);
  `logs:CreateLogGroup`/`AssociateKmsKey` on `/aws-glue/*` and
  `CreateLogStream`/`PutLogEvents` on its streams; `cloudwatch:PutMetricData`
  (no resource ARN exists) conditioned on namespace `Glue`; KMS on
  `kms_key_arn`; S3 list/read on the read set, read/write on
  `s3_write_buckets`, read on its own script prefix and read/write on its
  own temporary prefix.

## Differences from Cloud Posse

- One component instead of six; one role and one security configuration
  shared by every crawler and job in the instance.
- Scoped inline policies instead of attaching `AWSGlueServiceRole` (whose
  Glue/S3/EC2 statements use wildcard resources).
- Job scripts are uploaded by the component from inline source, instead of a
  pre-uploaded `script_location`.
- No Lake Formation grants (upstream's `aws_lakeformation_permissions`):
  this repo's accounts use the `IAM_ALLOWED_PRINCIPALS` model. Turning on
  Lake Formation access control would need them.
- No Glue connections, workflows, registries or schemas (upstream
  submodules) - the data pipeline uses none. Connection passwords are still
  encrypted account-wide once `enable_data_catalog_encryption` is set.

## Tests

`tests/glue.tftest.hcl` (mock provider): names, security configuration and
script encryption, Data Catalog encryption on/off, role trust, scoped
catalog (including the `default` database lookup)/logs/metrics/KMS/S3 statements, projection template derivation,
catalog vs S3 crawler targets, trigger key resolution, input validations,
and `enabled = false`.

```sh
cd components/terraform/glue
terraform init -backend=false && terraform test
```
