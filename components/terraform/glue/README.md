# glue

One Glue catalog database per instance with its tables, crawlers, Spark ETL jobs (scripts uploaded
from inline source), triggers, a shared IAM role, a KMS security configuration and, optionally, the
account's Data Catalog encryption. Folds Cloud Posse's six `aws-glue-*` components into one (owner
decision), as plain resources with scoped inline policies instead of `AWSGlueServiceRole`.

## Wiring

- No instance in the fnx stacks. `glue/defaults` reads `kms/main .key_arn`; the `data-pipeline`
  template creates `data-pipeline/glue-database`, reading its buckets' `.bucket_name`.
- Used by (in that template): the Firehose instances (`.database_name`, `.table_names`), `athena`
  (`.database_name`), `step-functions` (`.job_names`), `eventbridge` (`.crawler_names`).

## Notes

- `enable_data_catalog_encryption` is account-wide, one setting per account and region: enable it on
  exactly one instance. Every catalog reader (Firehose's schema role, Athena users, Step Functions)
  then needs `kms:Decrypt` on the key; without it Firehose Parquet conversion silently routes every
  record to `errors/`.
- Catalog-target crawlers must use `delete_behavior = "LOG"` (and the template uses
  `update_behavior = "LOG"`): the tables are Terraform-owned, so a rewriting crawler would drift.
- A table with `projection.enabled` gets its `storage.location.template` derived from the partition
  keys; Athena ignores catalog partitions on such tables, so they need no crawler.
- `jobs` require `assets_bucket_name` (scripts and `--TempDir` live there).
- No Lake Formation grants: the accounts use the `IAM_ALLOWED_PRINCIPALS` model.
- The database name is the instance name with hyphens replaced by underscores.
