# sns

One SNS topic per instance with its subscriptions, modelled on Cloud Posse's
[aws-sns-topic](https://github.com/cloudposse-terraform-components/aws-sns-topic)
component (same input and output names and defaults). The topic is encrypted
with a customer managed KMS key and always carries a topic policy: publishing
without TLS is denied, and publish grants for AWS services are limited to this
account by `aws:SourceAccount`.

## Deployed instances

None in the three fnx stacks yet. The abstract base `sns/defaults`
(`stacks/catalog/sns/defaults.yaml`) wires the key from `kms/main`; instances
inherit it and set `name`, `subscribers` and the allowed publishers.

## Inputs / outputs

| Key | Notes |
|---|---|
| `region`, `tags`, `name`, `kms_key_arn` (required) | `tags` must include a non-empty `Environment`; the topic is `<Environment>-<name>` (`.fifo` appended for FIFO). The key must be a KMS key ARN |
| `subscribers` ({}) | map of `{protocol, endpoint, endpoint_auto_confirms, raw_message_delivery, filter_policy, filter_policy_scope, subscription_role_arn, dead_letter_queue_arn}`. Protocols: sqs, lambda, https, email, email-json, sms, application, firehose (firehose needs `subscription_role_arn`); `dead_letter_queue_arn` sets the subscription's redrive policy |
| `allowed_aws_services_for_sns_published` ([]) | service principals allowed `sns:Publish`, each limited to this account by `aws:SourceAccount` |
| `allowed_iam_arns_for_sns_publish` ([]) | IAM role/user ARNs allowed `sns:Publish` (for other accounts; this account's principals only need an IAM policy) |
| `sns_topic_policy_json` ("") | extra policy JSON merged into the generated one as a source document; the generated statements (the TLS deny included) win on a `Sid` clash. Its statements are used as written and are **not** rescoped to this topic, so set each `Resource` to the topic ARN yourself. Allow statements are rejected if they use `NotPrincipal`, a principal with a wildcard inside it (`arn:aws:iam::*:root`), or principal `*` without a non-empty `Condition` |
| `delivery_policy` (null), `fifo_topic` (false), `content_based_deduplication` (false) | Cloud Posse's inputs; deduplication requires `fifo_topic` |
| `enabled` (true) | false creates nothing |
| out: `sns_topic_name`, `sns_topic_id`, `sns_topic_arn`, `sns_topic_owner`, `sns_topic_subscriptions` | Cloud Posse's outputs; subscriptions are ARNs keyed like `subscribers` |

## Dependencies / gotchas

- **Key policy.** A service publishing to the topic encrypts with the key as a
  service principal, which kms/main's root-account statement does not reach.
  kms/main covers EventBridge rules (`allow_eventbridge`'s
  `AllowEventBridgeSNSTopics`) and CloudWatch alarms
  (`allow_cloudwatch_alarms`), both on in every stack. Other publishers (for
  example S3 notifications) need their own key-policy statement.
- **SQS subscribers.** SNS delivers to a queue encrypted with kms/main through
  kms/main's `AllowSNS` statement (`allow_sns`, added with the sqs component
  and on in every stack). The queue itself must
  let `sns.amazonaws.com` `sqs:SendMessage` with an `aws:SourceArn` condition
  on this topic's ARN (the sqs component's `iam_policy`), or delivery fails.
- The generated policy replaces SNS's default policy. This account's IAM
  principals keep access through their IAM policies; add other accounts via
  `allowed_iam_arns_for_sns_publish`.
- `http` subscriptions are rejected; use `https`.

## Differences from Cloud Posse

- Plain resources instead of the `cloudposse/sns-topic` module; no
  `context.tf`/null-label, names come from `tags.Environment` and
  `default_tags` carries the tags.
- `kms_key_arn` is required (Cloud Posse defaults to the AWS-managed
  `alias/aws/sns`); `encryption_enabled` is dropped.
- The topic policy is always created and denies publishing without TLS;
  service grants carry `aws:SourceAccount` (Cloud Posse's have no condition).
  `sns_topic_policy_json` is merged in rather than replacing the policy
  (Cloud Posse replaces it), so the TLS deny cannot be dropped.
- Subscriptions take a per-subscriber `dead_letter_queue_arn` (an sqs
  instance's queue) instead of Cloud Posse's module-created DLQ
  (`sqs_dlq_enabled`, `sqs_queue_kms_*`, `sqs_dlq_*`, `fifo_queue_enabled`,
  `redrive_policy*`, trimmed).
- The outputs return what their names say (upstream wires them crosswise).
- Validations Cloud Posse does not have: the key ARN, subscriber protocols,
  firehose role, DLQ and publisher ARNs, and JSON inputs.

## Tests

`tests/sns.tftest.hcl` runs offline against the real provider with dummy
credentials, so the topic policy is rendered and asserted:

```
cd components/terraform/sns && terraform init -backend=false && terraform test
```

## Usage

```yaml
components:
  terraform:
    sns/alerts:
      metadata:
        component: sns
        inherits: [sns/defaults]
      vars:
        name: alerts
        allowed_aws_services_for_sns_published: ["events.amazonaws.com"]
        subscribers:
          oncall:
            protocol: https
            endpoint: https://events.example.com/sns
```

```
atmos terraform plan sns/alerts -s <stack>
```
