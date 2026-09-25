# kinesis

One AWS Kinesis Data Stream per instance, modelled on Cloud Posse's
[aws-kinesis-stream](https://github.com/cloudposse-terraform-components/aws-kinesis-stream)
component (which wraps
[cloudposse/terraform-aws-kinesis-stream](https://github.com/cloudposse/terraform-aws-kinesis-stream)).
Written as a plain resource, like this repo's other short-name root
components (`stepfunctions`, `sns`, `sqs`). Encryption is always
customer-managed KMS: there is no unencrypted (`NONE`) option, unlike the
upstream module.

## Deployed instances

`data-pipeline/kinesis-ingest` and `data-pipeline/kinesis-enriched` in
`stacks/catalog/templates/data-pipeline.yaml` (a template, not a deployed
stack). The abstract base `kinesis/defaults`
(`stacks/catalog/kinesis/defaults.yaml`) wires the key from `kms/main`;
instances inherit it and set `name`, `stream_mode`, `retention_period`,
`shard_level_metrics` and, as needed, `consumers`.

## Inputs / outputs

| Key | Notes |
|---|---|
| `region`, `tags`, `name`, `kms_key_id` (required) | `tags` must include a non-empty `Environment`; the stream is `<Environment>-<name>`. `kms_key_id` is a KMS alias, key ID or ARN — encryption is always KMS, so this is always required |
| `stream_mode` (`ON_DEMAND`) | `ON_DEMAND` or `PROVISIONED` |
| `shard_count` (`null`) | Required (and must be `> 0`) when `stream_mode` is `PROVISIONED`; must be left `null` for `ON_DEMAND`, which manages its own capacity. Enforced by a variable validation that rejects either mismatch at plan time |
| `retention_period` (`24`) | Hours records are retained; `24`-`8760` (1-365 days) |
| `shard_level_metrics` (`[]`) | Enhanced (shard-level) CloudWatch metrics to enable; any of `IncomingBytes`, `IncomingRecords`, `OutgoingBytes`, `OutgoingRecords`, `WriteProvisionedThroughputExceeded`, `ReadProvisionedThroughputExceeded`, `IteratorAgeMilliseconds` |
| `enforce_consumer_deletion` (`false`) | Allow the stream to be destroyed even with registered enhanced fan-out consumers |
| `consumers` (`{}`) | Map of `{enabled (true)}`, keyed by the AWS-registered consumer name (1-128 characters). Each enabled entry becomes its own `aws_kinesis_stream_consumer` (enhanced fan-out); `enabled = false` on an entry removes just that consumer without touching the stream |
| `enabled` (`true`) | `false` creates nothing, including any consumers |
| out: `stream_arn`, `stream_name`, `stream_id` | Always set when enabled |
| out: `consumer_arns` | Map of consumer name to ARN, for enabled entries in `consumers`. Empty map when none are enabled |
| out: `reader_kms_policy` | A ready-to-use IAM identity policy document (JSON string) granting `kms:Decrypt` on `kms_key_id`, scoped to this stream alone. Null when disabled |

## Dependencies / gotchas

- **Reader KMS grants.** Kinesis server-side encryption is enforced purely
  through IAM (unlike, for example, Step Functions' CloudWatch Logs
  delivery, which needs a `delivery.logs.amazonaws.com` key-policy grant):
  any principal the KMS key's own policy already delegates to (this repo's
  `kms/main` delegates to the account root, via `enable_default_policy`) can
  use the key once its own IAM identity policy allows it. A stream reader
  (a Lambda event source mapping polling the stream, a Firehose delivery
  stream, an application calling `GetRecords` directly) needs `kms:Decrypt`
  on `kms_key_id`. This component has no reader role of its own to attach
  that grant to, so it exposes the ready-made policy document as the
  `reader_kms_policy` output instead — `{Version, Statement: [{Sid:
  "AllowKinesisStreamKMSRead", Effect: "Allow", Action: ["kms:Decrypt"],
  Resource: kms_key_id, Condition: {StringEquals: {"kms:ViaService":
  "kinesis.<region>.amazonaws.com", "kms:EncryptionContext:aws:kinesis:arn":
  <this stream's ARN>}}}]}`, the same Resource/Condition pair AWS's own docs
  use for granting a reader (for example Firehose reading an encrypted
  source stream) access to a specific encrypted Kinesis stream's key. A
  reader wires it in via `!terraform.state` into whatever custom/inline
  policy input its own component exposes; see
  `stacks/catalog/templates/data-pipeline.yaml`'s `lambda-transformer` and
  `lambda-validator` instances, which set the `lambda` component's
  `custom_policy` to `!terraform.state data-pipeline/kinesis-ingest
  .reader_kms_policy` / `...kinesis-enriched .reader_kms_policy`
  respectively (the stream each one's `event_source_mappings` reads from).
- **Shard count and stream mode are cross-validated at plan time.**
  `shard_count` must be a positive number under `PROVISIONED` and `null`
  under `ON_DEMAND`; setting the wrong one fails the variable validation
  before any AWS call, rather than surfacing as an apply-time API error.
- **Consumers reference the stream by ARN**, so `aws_kinesis_stream_consumer`
  always depends on the stream resource itself (`aws_kinesis_stream.this[0]`)
  and is created only when the stream is (`enabled = false` removes both).

## Differences from Cloud Posse

- Plain resource instead of the `cloudposse/terraform-aws-kinesis-stream`
  module; no `context.tf`/null-label, names come from `tags.Environment` and
  `default_tags` carries the tags.
- Encryption is mandatory (always `KMS`); Cloud Posse's module defaults to
  `NONE` and leaves `KMS` opt-in via `encryption_type`/`kms_key_id`.
- `consumers` is a map keyed by consumer name (matching this repo's
  for-each-over-a-map convention for repeatable sub-resources, as in
  `eventbridge`'s `targets`), rather than Cloud Posse's `list(string)` of
  stream-consumer names; each entry can be individually disabled via
  `enabled` without removing it from the map.
- Adds the `reader_kms_policy` output, which Cloud Posse's component has no
  equivalent for: it assumes the caller already knows how to grant its own
  reader roles `kms:Decrypt`, whereas this component hands back the whole
  policy document so a reader never has to reconstruct the encryption
  context condition (or the key ARN) itself.
