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
| `region`, `tags`, `name`, `kms_key_id` (required) | `tags` must include a non-empty `Environment`; the stream is `<Environment>-<name>`. `kms_key_id` must be a full KMS key ARN (not an alias or bare key ID — it is used verbatim as an IAM policy `Resource`, which only matches ARNs) — encryption is always KMS, so this is always required |
| `stream_mode` (`ON_DEMAND`) | `ON_DEMAND` or `PROVISIONED` |
| `shard_count` (`null`) | Required (and must be `> 0`) when `stream_mode` is `PROVISIONED`; must be left `null` for `ON_DEMAND`, which manages its own capacity. Enforced by a variable validation that rejects either mismatch at plan time |
| `retention_period` (`24`) | Hours records are retained; `24`-`8760` (1-365 days) |
| `shard_level_metrics` (`[]`) | Enhanced (shard-level) CloudWatch metrics to enable; any of `IncomingBytes`, `IncomingRecords`, `OutgoingBytes`, `OutgoingRecords`, `WriteProvisionedThroughputExceeded`, `ReadProvisionedThroughputExceeded`, `IteratorAgeMilliseconds` |
| `enforce_consumer_deletion` (`false`) | Allow the stream to be destroyed even with registered enhanced fan-out consumers |
| `consumers` (`{}`) | Map of `{enabled (true)}`, keyed by the AWS-registered consumer name (1-128 characters). Each enabled entry becomes its own `aws_kinesis_stream_consumer` (enhanced fan-out); `enabled = false` on an entry removes just that consumer without touching the stream |
| `additional_policy_json` (`null`) | Another IAM policy document (JSON, `{Version, Statement}`) - typically another kinesis instance's own `reader_policy`/`writer_policy` output - whose `Statement` entries are folded into this stream's `combined_policy` output (never into `writer_policy`, which always stays exactly this stream's own two statements). Each entry's `Sid` is rewritten (prefixed `Additional`) so it can never collide with this stream's own Sids, even when the document passed in is itself a `writer_policy`-shaped output. Must be `null` or decode to an object with a `Statement` key (enforced by a variable validation). See "Combining grants across two streams" below |
| `enabled` (`true`) | `false` creates nothing, including any consumers |
| out: `stream_arn`, `stream_name`, `stream_id` | Always set when enabled |
| out: `consumer_arns` | Map of consumer name to ARN, for enabled entries in `consumers`. Empty map when none are enabled |
| out: `reader_policy` | A ready-to-use IAM identity policy document (JSON string) for a stream reader: the Kinesis read actions (`GetRecords`, `GetShardIterator`, `DescribeStream[Summary]`, `ListShards`) scoped to the stream, enhanced fan-out actions (`SubscribeToShard`, `DescribeStreamConsumer`) scoped to any registered consumer ARNs, and `kms:Decrypt` on `kms_key_id` scoped to this stream alone. `ListStreams` is deliberately not included - it supports no resource-level permissions, so scoping it to this stream's ARN would never actually grant it. Null when disabled |
| out: `writer_policy` | A ready-to-use IAM identity policy document (JSON string) for a stream writer: `kinesis:PutRecord`/`PutRecords`/`DescribeStreamSummary` scoped to the stream, and `kms:GenerateDataKey` on `kms_key_id` scoped to this stream alone. Always exactly these two statements, regardless of `additional_policy_json` - attaching it to a role can never silently grant more than "write to this stream". Null when disabled |
| out: `combined_policy` | `writer_policy`'s own two statements plus, when `additional_policy_json` is set, that document's (Sid-rewritten) `Statement` entries too. Use this - not `writer_policy` - for a consumer that needs another stream's grants folded in alongside this stream's write grant. Null when disabled |

## Dependencies / gotchas

- **Reader/writer KMS grants.** Kinesis server-side encryption is enforced
  purely through IAM (unlike, for example, Step Functions' CloudWatch Logs
  delivery, which needs a `delivery.logs.amazonaws.com` key-policy grant):
  any principal the KMS key's own policy already delegates to (this repo's
  `kms/main` delegates to the account root, via `enable_default_policy`) can
  use the key once its own IAM identity policy allows it. A stream reader
  (a Lambda event source mapping polling the stream, a Firehose delivery
  stream, an application calling `GetRecords` directly) needs the Kinesis
  read actions plus `kms:Decrypt` on `kms_key_id`; a stream writer (an
  application calling `PutRecord`/`PutRecords`) needs the Kinesis write
  actions plus `kms:GenerateDataKey`. This component has no reader/writer
  role of its own to attach those grants to, so it exposes the ready-made
  policy documents as the `reader_policy` / `writer_policy` outputs instead
  — see the table above for their exact statements, and
  `components/terraform/kinesis/main.tf` for the literal JSON shape. Both
  KMS statements use the same Resource/Condition pair AWS's own docs use for
  granting a principal (for example Firehose reading an encrypted source
  stream) access to a specific encrypted Kinesis stream's key: `Resource:
  kms_key_id`, `Condition: {StringEquals: {"kms:ViaService":
  "kinesis.<region>.amazonaws.com", "kms:EncryptionContext:aws:kinesis:arn":
  <this stream's ARN>}}`. A consumer of a single stream wires the relevant
  output in via `!terraform.state` into whatever custom/inline policy input
  its own component exposes; see
  `stacks/catalog/templates/data-pipeline.yaml`'s `lambda-validator`
  instance, which sets the `lambda` component's `custom_policy` to
  `!terraform.state data-pipeline/kinesis-enriched .reader_policy` (the
  stream its intended event source would read from — the `lambda` component
  does not yet implement `event_source_mappings`, so this grant is
  forward-looking).
- **Combining grants across two streams.** A single consumer that needs
  grants on two different streams — `lambda-transformer` reads
  `kinesis-ingest` (an enhanced-fan-out/event-source reader) and writes
  `kinesis-enriched` (its handler calls `PutRecord`/`PutRecords` against
  `OUTPUT_STREAM`) — can't get there with `!terraform.state` alone: it reads
  one component's one output, never combines two components' outputs into
  one value. It's tempting to reach for an Atmos Go template
  (`atmos.Component` can read a second component's live output inline), but
  that requires live state even at `atmos describe component`/`atmos
  validate stacks` time (Go templates render unconditionally, unlike YAML
  functions like `!terraform.state`, which `--process-functions=false`
  skips) — breaking those commands for the *whole* stack the moment any
  instance in it uses `atmos.Component`, before anything in the stack has
  ever been applied. (Verified directly: pointing `lambda-transformer`'s
  `custom_policy` at an `atmos.Component`-based template made `atmos
  describe stacks --process-functions=false` for that stack fail outright,
  with no live state, exactly the state this repo is always in until first
  apply.) `additional_policy_json` avoids that: it moves the merge into
  Terraform instead. `kinesis-enriched`'s instance sets it to
  `!terraform.state data-pipeline/kinesis-ingest .reader_policy` (a single,
  ordinary, `--process-functions=false`-skippable call, `kinesis-ingest`
  added to `kinesis-enriched`'s own `dependencies.components`), and
  `kinesis-enriched`'s `combined_policy` output (its own two write
  statements, `writer_policy`'s contents) folds that document's `Statement`
  entries in via `jsondecode(var.additional_policy_json).Statement` inside
  Terraform - `writer_policy` itself is left untouched, so anything else
  that attaches `kinesis-enriched`'s plain `writer_policy` stays scoped to
  `kinesis-enriched` alone. `lambda-transformer`'s `custom_policy` then reads
  that one, already-combined output: `!terraform.state
  data-pipeline/kinesis-enriched .combined_policy` — a single
  `!terraform.state` call, same as every other consumer here.
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
- Adds the `reader_policy` / `writer_policy` / `combined_policy` outputs
  (and the `additional_policy_json` input that lets `combined_policy` absorb
  another instance's), which Cloud Posse's component has no equivalent for:
  it assumes the caller already knows how to grant its own reader/writer
  roles the right Kinesis actions and `kms:Decrypt`/`kms:GenerateDataKey`,
  whereas this component hands back the whole policy documents so a
  consumer never has to reconstruct the encryption context condition (or
  the key ARN)
  itself.
