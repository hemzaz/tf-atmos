# athena

One Athena workgroup per instance with its named queries and extra data catalogs. Modelled on Cloud
Posse `aws-athena` as plain resources; results are always `SSE_KMS` with a customer managed key and
the workgroup configuration is always enforced.

## Wiring

- No instance in the fnx stacks. `athena/defaults` reads `kms/main .key_arn`; the `data-pipeline`
  template creates `data-pipeline/athena`, reading the `s3-athena-results` bucket
  (`output_location`) and `glue-database .database_name`.
- Deploys in the `deploy-full-stack` platform layer, after `glue` (compute). The
  `stepfunctions` instances sharing that layer cannot read its state:
  `data-pipeline/stepfunctions/daily-etl` names the workgroup (`<Environment>-<name>`) instead.

## Notes

- Athena has no service role: queries run as the caller. Attach the `query_policy` output (workgroup,
  results bucket, key, Glue read on `query_database_names`, S3 read on `query_source_buckets`) to
  the querying principal. No key-policy statement is needed.
- The results bucket is a separate `s3` instance; this component does not create it or any database
  (databases come from `glue`).
- `bytes_scanned_cutoff_per_query` is `null` or at least 10 MB.
