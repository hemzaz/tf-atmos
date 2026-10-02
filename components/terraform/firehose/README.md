# firehose

One Amazon Data Firehose delivery stream per instance, named `<Environment>-<name>`, delivering to
S3 (`extended_s3`). The source is direct put or a Kinesis data stream. Optional: Parquet/ORC
conversion against a Glue table, dynamic partitioning (JQ or Lambda partition keys) and a Lambda
processor. Modelled on Cloud Posse `aws-kinesis-firehose-stream` as plain resources; the
deviations are listed at the top of `main.tf`.

## Wiring

- No instance in the fnx stacks. `firehose/defaults` reads `kms/main .key_arn`; an instance sets
  `s3_bucket_arn` from an `s3` instance's `.bucket_arn` and, for a Kinesis source,
  `kinesis_source_stream_arn` (`.stream_arn`) and `kinesis_source_kms_key_arn` (the stream's key),
  listing those instances in `dependencies.components`.
- Conversion reads a `glue` instance's `.database_name` and a table name (`.table_names`) into
  `data_format_conversion.schema_configuration`; a Lambda processor reads a `lambda` instance's
  `.function_arn` (or `.alias_arn`) into `processor_lambda_arn`.
- It deploys in the `data` layer of `workflows/deploy-full-stack.yaml`, after `kms`, `s3` and
  `lambda`. A `kinesis` or `glue` instance it reads must deploy in an earlier layer.
- `stacks/catalog/templates/data-pipeline.yaml` (`data-pipeline/firehose-raw`,
  `data-pipeline/firehose-processed`) predates this component and still uses the old nested
  `kinesis_source_configuration`/`s3_configuration` inputs; it needs porting.
- Consumers read `.delivery_stream_name` (the `AWS/Firehose` `DeliveryStreamName` dimension) and
  `.delivery_stream_arn` (producers' `firehose:PutRecord*` grants, EventBridge targets).

## Notes

- Two roles, both trusting `firehose.amazonaws.com` for this account only (`aws:SourceAccount`):
  `<Environment>-<name>-delivery` writes to the one bucket, uses `kms_key_arn` through S3 only and
  writes to the delivery log stream; `<Environment>-<name>-source` (Kinesis source only) reads the
  one stream and decrypts it through Kinesis only. With the optional features the delivery role
  also reads the one Glue table (catalog, database and table ARNs) and invokes the one Lambda (the
  given ARN and its unqualified form).
- A direct put stream is always encrypted: with `server_side_encryption_kms_key_arn` when set,
  otherwise an AWS owned key. A Kinesis source takes no stream encryption (validated); its records
  stay encrypted by the source stream's key.
- The deployer needs `kms:CreateGrant` on `server_side_encryption_kms_key_arn`: Firehose uses a
  grant, not the roles, for stream encryption.
- `kms_key_arn` encrypts objects and the `/aws/kinesisfirehose/<Environment>-<name>` log group, so
  its key policy must allow CloudWatch Logs (`kms/main` does).
- An `s3_prefix` with `!{...}` expressions needs `s3_error_output_prefix`, and an error prefix with
  expressions needs `!{firehose:error-output-type}` (validated; Firehose rejects both otherwise).
  `!{firehose:error-output-type}` is rejected in `s3_prefix`, partition keys in the error prefix.
- The source stream must be in the component's region.
- Conversion: the Glue table (a `glue` component table, or one already in the catalog) must exist
  before the stream, and its columns are the schema; records that do not match go to the error
  prefix. An encrypted Data Catalog needs `schema_configuration.kms_key_arn` (`kms:Decrypt`
  through Glue), or every record fails silently. Conversion needs `buffering_size >= 64` and
  `compression_format = "UNCOMPRESSED"` (compression is the serializer's; validated).
- Dynamic partitioning: billed per GB processed and per S3 object delivered on top of ingestion,
  and high-cardinality keys multiply objects; keep keys coarse. It needs `buffering_size >= 64`, an
  `s3_prefix` using at least one partition key, and every `!{partitionKeyFromQuery:<key>}` defined
  in `jq_queries` (validated). Firehose only allows turning it on when the stream is created (an
  existing stream cannot be switched to it in place).
