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
| `enabled` (true) | false creates nothing |
| out: `cloudwatch_logs_log_group_arn`, `cloudwatch_logs_log_group_name`, `cloudwatch_event_rule_arn`, `cloudwatch_event_rule_name` | Cloud Posse's outputs |
| out: `event_bus_name`, `event_bus_arn`, `event_archive_arn` | the bus the rule is on (the created one, or `event_bus_name`); ARNs are null when not created |

## Dependencies / gotchas

- **Key policy.** CloudWatch Logs and EventBridge use the key as service
  principals, so the key policy must allow `logs.<region>.amazonaws.com`
  and `events.amazonaws.com`. With this repo's kms component that is
  `key_service_users` on the key instance. The root-only default policy is
  not enough, and apply fails on the log group without it.
- EventBridge writes to the log group through a CloudWatch Logs resource
  policy (`aws_cloudwatch_log_resource_policy`, as in Cloud Posse), not a
  role. An account holds at most 10 such policies per region.
- Schema discovery is not offered: EventBridge does not run it on a bus
  encrypted with a customer managed key, and every bus here is.

## Differences from Cloud Posse

- Plain resources instead of the `cloudposse/cloudwatch-logs` and
  `cloudposse/cloudwatch-events` modules, like the other root components
  here; no `context.tf`/null-label, names come from `tags.Environment` and
  `default_tags` carries the tags.
- Added: `kms_key_arn` (Cloud Posse leaves the log group unencrypted),
  `create_event_bus`/`event_bus_name` (Cloud Posse only uses the default
  bus), `archive_enabled`/`archive_retention_days`, `enabled`, and the
  `event_bus_*`/`event_archive_arn` outputs.
- Validations Cloud Posse does not have: the key ARN, the pattern is a
  non-empty object, the retention is one CloudWatch accepts, and an archive
  needs a created bus.

## Tests

`tests/eventbridge.tftest.hcl` runs against a mock provider (no credentials):

```
cd components/terraform/eventbridge && terraform init -backend=false && terraform test
```

## Usage

```
atmos terraform plan <instance> -s <stack>   # after adding an instance
```
