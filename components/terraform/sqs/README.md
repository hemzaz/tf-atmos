# sqs

One SQS queue per instance, with an optional dead-letter queue, modelled on
Cloud Posse's
[aws-sqs-queue](https://github.com/cloudposse-terraform-components/aws-sqs-queue)
component (same input names and defaults, and its `iam_policy` queue policy).
Both queues are encrypted with a customer managed KMS key.

## Deployed instances

None in the three fnx stacks yet. The abstract base `sqs/defaults`
(`stacks/catalog/sqs/defaults.yaml`) wires the key from `kms/main`; instances
inherit it and set `name` and, as needed, `dlq_enabled` and `iam_policy`.

## Inputs / outputs

| Key | Notes |
|---|---|
| `region`, `tags`, `name`, `kms_key_arn` (required) | `tags` must include a non-empty `Environment`; the queue is `<Environment>-<name>` (`.fifo` appended for FIFO), at most 80 characters. The key must be a KMS key ARN; SQS-managed SSE is never used |
| `visibility_timeout_seconds` (30), `message_retention_seconds` (345600), `max_message_size` (262144), `delay_seconds` (0), `receive_wait_time_seconds` (0), `kms_data_key_reuse_period_seconds` (300) | Cloud Posse's defaults, validated to the ranges SQS accepts |
| `fifo_queue` (false), `content_based_deduplication` (false), `deduplication_scope`, `fifo_throughput_limit` (null) | FIFO settings; the last three require `fifo_queue` |
| `dlq_enabled` (false), `dlq_name_suffix` (`dlq`), `dlq_max_receive_count` (5), `dlq_message_retention_seconds` (1209600) | a DLQ `<Environment>-<name>-<suffix>`, same key, with a redrive policy on the queue and a redrive-allow policy on the DLQ that accepts only this queue |
| `iam_policy` ([]), `iam_policy_limit_to_current_account` (true) | Cloud Posse's queue policy: `aws_iam_policy_document` statements, each scoped to the queue ARN (`resources`/`not_resources` must be unset); the flag adds `aws:SourceAccount = <this account>` to every Allow statement that does not set it already (Deny statements are left unnarrowed). Allow statements must name principals and may not use wildcard actions (`*`, `sqs:*`), a `*` principal or one with a wildcard inside it (`arn:aws:iam::*:root`), `not_principals` or `not_actions` (no public queue). An Allow for a `Service` principal must pin the caller, since a service acts for whoever calls it: the account flag does (when the statement has no `aws:SourceAccount` of its own), or a condition on `aws:SourceAccount`, `aws:SourceArn`, `aws:SourceOwner`, `aws:SourceOrgID`, `aws:PrincipalOrgID`, `aws:PrincipalAccount` or `aws:PrincipalArn` (any case), under a positive operator (not `...Not...`, `...IfExists`, `Null` or `ForAllValues:...`, which let a caller without the key through) and with no value made only of wildcards (`*`, `?*`). Deny statements take `actions` or `not_actions` |
| `enabled` (true) | false creates nothing |
| out: `queue_id`, `queue_arn`, `queue_name`, `queue_url` | the queue (`queue_id` is the URL, as in SQS) |
| out: `dead_letter_queue_id`, `dead_letter_queue_arn`, `dead_letter_queue_name`, `dead_letter_queue_url` | null unless `dlq_enabled` |

## Dependencies / gotchas

- **Key policy.** AWS services that send to the queue encrypt with the key as
  service principals, which kms/main's root-account statement does not reach.
  kms/main covers two producers in every stack: EventBridge rules and bus
  dead-letter queues through `allow_eventbridge`'s `AllowEventBridgeSQSQueues`
  statement (this account's `rule/*` and `event-bus/*`), and SNS topics through `allow_sns`'s `AllowSNS` (this account's
  topics). Both are limited to this account and region by
  `aws:SourceAccount`/`aws:SourceArn`. Other producers (for example S3 event
  notifications) need their own statement.
- **Queue policy.** A service producer also needs `sqs:SendMessage` in the
  queue policy. For an EventBridge rule target (or an EventBridge bus DLQ):

  ```yaml
  iam_policy:
    - statements:
        - sid: AllowEventBridgeRule
          effect: Allow
          actions: ["sqs:SendMessage"]
          principals:
            - type: Service
              identifiers: ["events.amazonaws.com"]
          conditions:
            - test: ArnEquals
              variable: aws:SourceArn
              values: ["<rule or bus ARN>"]
  ```

  For an SNS subscription use `sns.amazonaws.com` and the topic ARN.
- `iam_policy` applies to the main queue only. For an EventBridge bus DLQ
  (eventbridge's `event_bus_dlq_arn`), use a separate sqs instance's
  `queue_arn`, whose `iam_policy` lets the bus send.
- With `iam_policy_limit_to_current_account` on, statements whose principals
  are IAM roles never match (`aws:SourceAccount` is only set on
  service-to-service requests); set it to false for those.

## Differences from Cloud Posse

- Plain resources instead of the `terraform-aws-modules/sqs` and
  `cloudposse/iam-policy` modules; no `context.tf`/null-label, names come
  from `tags.Environment` and `default_tags` carries the tags.
- `kms_key_arn` is required and encrypts both queues; the
  `sqs_managed_sse_enabled`, `kms_master_key_id` and `dlq_kms_master_key_id`
  inputs are dropped.
- The single `sqs_queue` object output is flattened into `queue_*` and
  `dead_letter_queue_*` outputs (the upstream module's names).
- The DLQ inherits the queue's FIFO and size settings instead of separate
  `dlq_*` inputs, and keeps messages 14 days by default (Cloud Posse: the
  SQS default, 4 days) so failed messages outlive the source queue.
- Trimmed: `dlq_redrive_allow_policy` (the DLQ always accepts only this
  queue) and `dlq_tags`.
- Validations Cloud Posse does not have: the key ARN, numeric ranges, FIFO
  settings requiring `fifo_queue`, no wildcard queue-policy actions or
  principals, service principals pinned to their caller, and
  preconditions on the 80-character queue name limit.

## Tests

`tests/sqs.tftest.hcl` runs offline against the real provider with dummy
credentials, so the queue policy is rendered and asserted:

```
cd components/terraform/sqs && terraform init -backend=false && terraform test
```

## Usage

```yaml
components:
  terraform:
    sqs/orders:
      metadata:
        component: sqs
        inherits: [sqs/defaults]
      vars:
        name: orders
        dlq_enabled: true
```

```
atmos terraform plan sqs/orders -s <stack>
```
