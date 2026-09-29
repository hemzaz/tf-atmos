# kinesis

One Kinesis Data Stream per instance, always encrypted with a customer managed key (no `NONE`
option, unlike Cloud Posse), with optional enhanced fan-out consumers. Modelled on Cloud Posse
`aws-kinesis-stream` as a plain resource. It also outputs ready-made IAM policy documents for
readers and writers.

## Wiring

- No instance in the fnx stacks. `kinesis/defaults` reads `kms/main .key_arn`; the `data-pipeline`
  template creates `data-pipeline/kinesis-ingest` and `data-pipeline/kinesis-enriched`.
- Consumers read `.stream_arn`, `.stream_name`, and attach `.reader_policy`, `.writer_policy` or
  `.combined_policy` to their own role (for example the `lambda` component's `custom_policy`).

## Notes

- `kms_key_id` must be a full key ARN: it is used verbatim as an IAM `Resource`. Readers need
  `kms:Decrypt` and writers `kms:GenerateDataKey` through IAM; the output policies already scope them
  by `kms:ViaService` and the stream's encryption context.
- `shard_count` is required under `PROVISIONED` and must be `null` under `ON_DEMAND` (validated).
- `ListStreams` is not in `reader_policy`: it has no resource-level permissions.

## Combining grants across two streams

A consumer that reads one stream and writes another needs both grants in one policy, and
`!terraform.state` reads a single output. Set the written stream's `additional_policy_json` to the
read stream's `reader_policy`; its `combined_policy` output then holds both (with rewritten Sids),
while `writer_policy` stays scoped to its own stream. `data-pipeline/lambda-transformer` uses
`kinesis-enriched .combined_policy` this way. Do not use `atmos.Component` templates instead: they
need live state even for `atmos describe stacks --process-functions=false`.
