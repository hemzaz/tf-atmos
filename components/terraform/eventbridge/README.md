# eventbridge

One EventBridge rule per instance that delivers every matching event to a
CloudWatch log group, modelled on Cloud Posse's
[aws-eventbridge](https://github.com/cloudposse-terraform-components/aws-eventbridge)
component (same inputs and outputs). This repo adds an optional custom event
bus with an archive, and encrypts the log group, bus and archive with a
customer managed KMS key.

## Deployed instances

None in the three fnx stacks yet. The abstract base `eventbridge/defaults`
(`stacks/catalog/eventbridge/defaults.yaml`) wires the key from `kms/main`;
instances inherit it and set `name` and `cloudwatch_event_rule_pattern`.

## Inputs / outputs

| Key | Notes |
|---|---|
| `region`, `tags`, `name`, `kms_key_arn` (required) | `tags` must include a non-empty `Environment`; the rule, log group (`/aws/events/<Environment>-<name>`) and bus/archive are named `<Environment>-<name>`. The key must be a KMS key ARN |
| `cloudwatch_event_rule_pattern` (`{source = ["aws.ec2"]}`), `cloudwatch_event_rule_description` (""), `event_log_retention_in_days` (3) | Cloud Posse's inputs and defaults; the pattern is an object, JSON-encoded here; retention must be a CloudWatch Logs value |
| `create_event_bus` (false), `event_bus_name` (`default`) | create a bus `<Environment>-<name>` for the rule, or put the rule on an existing one (another instance's `event_bus_name` output) |
| `archive_enabled` (false), `archive_retention_days` (30, 0 = forever) | archive every event on the created bus; requires `create_event_bus` |
| `event_bus_dlq_arn` (null) | ARN of an SQS queue EventBridge uses as a dead-letter queue for the created bus; only used when `create_event_bus` is true |
| `enabled` (true) | false creates nothing |
| out: `cloudwatch_logs_log_group_arn`, `cloudwatch_logs_log_group_name`, `cloudwatch_event_rule_arn`, `cloudwatch_event_rule_name` | Cloud Posse's outputs |
| out: `event_bus_name`, `event_bus_arn`, `event_archive_arn` | the bus the rule is on (the created one, or `event_bus_name`); ARNs are null when not created |

## Dependencies / gotchas

- **Key policy.** CloudWatch Logs and EventBridge use the key as service
  principals, so the key policy must allow `logs.<region>.amazonaws.com` and
  `events.amazonaws.com`. With this repo's kms component that means setting
  `allow_cloudwatch_logs = true` and `allow_eventbridge = true` on the key
  instance (both scoped: logs by `kms:EncryptionContext:aws:logs:arn`, events
  by `kms:EncryptionContext:aws:events:event-bus:arn`, DescribeKey by
  `aws:SourceAccount`) — not the library's unconditioned
  `key_service_users`. The root-only default policy is not enough, and apply
  fails on the log group without it.
- EventBridge writes to the log group through a CloudWatch Logs resource
  policy (`aws_cloudwatch_log_resource_policy`), scoped to this log group
  alone via `resource_arn` — see "Differences from Cloud Posse" below.
- A CMK-encrypted bus should have a dead-letter queue: set `event_bus_dlq_arn`
  so events that fail encrypt/decrypt (for example after a key-policy change
  or key disable) are kept, not dropped.
- Schema discovery is not offered on a bus encrypted with a customer managed
  key. That only applies to a bus this component creates (`create_event_bus`);
  the default bus, which this component does not encrypt, is unaffected.

## Differences from Cloud Posse

- Plain resources instead of the `cloudposse/cloudwatch-logs` and
  `cloudposse/cloudwatch-events` modules, like the other root components
  here; no `context.tf`/null-label, names come from `tags.Environment` and
  `default_tags` carries the tags.
- Added: `kms_key_arn` (Cloud Posse leaves the log group unencrypted),
  `create_event_bus`/`event_bus_name` (Cloud Posse only uses the default
  bus), `archive_enabled`/`archive_retention_days`, `event_bus_dlq_arn`,
  `enabled`, and the `event_bus_*`/`event_archive_arn` outputs.
- The `aws_cloudwatch_log_resource_policy` is resource-scoped
  (`resource_arn = aws_cloudwatch_log_group.this[0].arn`, provider >= 6.36),
  not account-scoped (`policy_name`) as in Cloud Posse. Account-scoped
  policies are capped at 10 per region, shared with every other component and
  service in the account; a resource-scoped policy attaches to this log group
  alone and consumes none of that quota. It also carries an
  `aws:SourceAccount` condition Cloud Posse's policy does not have.
- Validations Cloud Posse does not have: the key ARN, the pattern is a
  non-empty object, the retention is one CloudWatch accepts, an archive needs
  a created bus, the DLQ ARN, and a precondition that the archive name
  (`<Environment>-<name>`) is 48 characters or fewer.

## Tests

`tests/eventbridge.tftest.hcl` runs against a mock provider (no credentials):

```
cd components/terraform/eventbridge && terraform init -backend=false && terraform test
```

## Usage

```
atmos terraform plan <instance> -s <stack>   # after adding an instance
```
