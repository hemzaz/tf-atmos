# firehose

One Amazon Data Firehose delivery stream per instance, named `<Environment>-<name>`, delivering to
S3 (`extended_s3`). The source is direct put or a Kinesis data stream. Modelled on Cloud Posse
`aws-kinesis-firehose-stream` as plain resources; the deviations are listed at the top of
`main.tf`.

Not yet supported (part 2): data format conversion (Glue schema, Parquet) and dynamic
partitioning. `s3_prefix` rejects `!{partitionKeyFrom...}` until then.

## Wiring

- No instance in the fnx stacks. `firehose/defaults` reads `kms/main .key_arn`; an instance sets
  `s3_bucket_arn` from an `s3` instance's `.bucket_arn` and, for a Kinesis source,
  `kinesis_source_stream_arn` (`.stream_arn`) and `kinesis_source_kms_key_arn` (the stream's key),
  listing those instances in `dependencies.components`.
- It deploys in the `data` layer of `workflows/deploy-full-stack.yaml`, after `kms`, `s3` and
  `lambda`. A `kinesis` instance it reads must deploy in an earlier layer.
- `stacks/catalog/templates/data-pipeline.yaml` (`data-pipeline/firehose-raw`,
  `data-pipeline/firehose-processed`) predates this component and still uses the old nested
  `kinesis_source_configuration`/`s3_configuration` inputs; it needs porting.
- Consumers read `.delivery_stream_name` (the `AWS/Firehose` `DeliveryStreamName` dimension) and
  `.delivery_stream_arn` (producers' `firehose:PutRecord*` grants, EventBridge targets).

## Notes

- Two roles, both trusting `firehose.amazonaws.com` for this account only (`aws:SourceAccount`):
  `<Environment>-<name>-delivery` writes to the one bucket, uses `kms_key_arn` through S3 only and
  writes to the delivery log stream; `<Environment>-<name>-source` (Kinesis source only) reads the
  one stream and decrypts it through Kinesis only.
- A direct put stream is always encrypted: with `server_side_encryption_kms_key_arn` when set,
  otherwise an AWS owned key. A Kinesis source takes no stream encryption (validated); its records
  stay encrypted by the source stream's key.
- The deployer needs `kms:CreateGrant` on `server_side_encryption_kms_key_arn`: Firehose uses a
  grant, not the roles, for stream encryption.
- `kms_key_arn` encrypts objects and the `/aws/kinesisfirehose/<Environment>-<name>` log group, so
  its key policy must allow CloudWatch Logs (`kms/main` does).
- An `s3_prefix` with `!{...}` expressions needs `s3_error_output_prefix`, and an error prefix with
  expressions needs `!{firehose:error-output-type}` (validated; Firehose rejects both otherwise).
- The source stream must be in the component's region.
