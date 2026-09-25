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
| `schedule_expression` (null) | `cron(...)` or `rate(...)`: the rule fires on this schedule instead of matching events, and `cloudwatch_event_rule_pattern` is ignored. EventBridge only runs schedules on the default bus, so it rejects `create_event_bus` or another `event_bus_name`. Its name is terraform-aws-modules/eventbridge's |
| `create_event_bus` (false), `event_bus_name` (`default`) | create a bus `<Environment>-<name>` for the rule, or put the rule on an existing one (another instance's `event_bus_name` output) |
| `archive_enabled` (false), `archive_retention_days` (30, 0 = forever) | archive every event on the created bus; requires `create_event_bus` |
| `event_bus_dlq_arn` (null) | ARN of an SQS queue EventBridge uses as a dead-letter queue for the created bus; only used when `create_event_bus` is true |
| `targets` (`{}`) | further targets of the rule, keyed by target ID (at most 4: a rule takes 5 and the log group is one). Each has `arn`, and optionally `role_arn`, `input_path` or `input_transformer` (`input_paths`, `input_template`), `dead_letter_config.arn` (a standard SQS queue, not FIFO), `retry_policy` (`maximum_event_age_in_seconds` 60-86400, `maximum_retry_attempts` 0-185), `sqs_message_group_id` (required for a `.fifo` queue), `ecs_target` (required for an ECS cluster: task definition, count, launch type, network) and `batch_target` (required for a Batch job queue: job definition and name). See "Targets" below |
| `enabled` (true) | false creates nothing |
| out: `cloudwatch_logs_log_group_arn`, `cloudwatch_logs_log_group_name`, `cloudwatch_event_rule_arn`, `cloudwatch_event_rule_name` | Cloud Posse's outputs |
| out: `event_bus_name`, `event_bus_arn`, `event_archive_arn` | the bus the rule is on (the created one, or `event_bus_name`); ARNs are null when not created |

## Targets

The log group is always a target. `targets` adds more, each an
`aws_cloudwatch_event_target` on the rule's bus. How EventBridge is allowed to
deliver depends on the target:

- **Lambda functions**: the component creates an `aws_lambda_permission` that
  lets `events.amazonaws.com` invoke the function from this rule only
  (`source_arn` is the rule ARN). Don't also set the lambda component's
  `cloudwatch_source_arn` for the same rule. The permission lives in this
  component's state, not the function's: if the function is destroyed and
  recreated (a rename, or anything else that replaces it), its resource policy
  starts empty and the rule cannot invoke it until this instance is applied
  again, which recreates the permission.
- **SQS queues** (and SNS topics): EventBridge sends under the queue's
  resource policy, which this component does not create. With this repo's sqs
  component, give the queue an `iam_policy` statement that allows
  `events.amazonaws.com` `sqs:SendMessage`, conditioned on `aws:SourceArn`
  = the rule ARN (`arn:aws:events:<region>:<account>:rule/<bus>/<rule>`
  on a custom bus; the sqs component adds `aws:SourceAccount` itself). The
  same goes for a target's `dead_letter_config` queue and for the bus's
  `event_bus_dlq_arn` queue (`aws:SourceArn` = the bus ARN there). The rule
  ARN only depends on names, so the queue policy can be written before the
  rule exists: queues first, rules second, no dependency cycle
  (`stacks/catalog/templates/microservices-platform.yaml` does this).
- **KMS**: a queue encrypted with a customer managed key also needs the key
  policy to let `events.amazonaws.com` use it; this repo's kms component does
  that under `allow_eventbridge` (`AllowEventBridgeSQSQueues`, scoped to
  this account's rules and buses).
- **ECS and Batch**: an ECS cluster target needs `ecs_target` (the task
  definition to run, `task_count`, `launch_type`, and `network_configuration`
  for Fargate), a Batch job queue target needs `batch_target` (job definition
  and name, optional `array_size`/`job_attempts`); both also need `role_arn`.
- **Everything else** EventBridge reaches with an IAM role: `role_arn` is
  required for Step Functions, Kinesis, Firehose, ECS, Batch and EventBridge
  (another bus, API destinations) targets, and rejected for Lambda, SQS, SNS
  and CloudWatch Logs, which use resource policies. This component does not
  create that role.

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
  `schedule_expression` (Cloud Posse's rule only matches events), `enabled`,
  and the `event_bus_*`/`event_archive_arn` outputs.
- `targets` replaces the single target of Cloud Posse's
  `cloudposse/cloudwatch-events` module (`cloudwatch_event_target_arn`,
  `cloudwatch_event_target_role_arn`, `cloudwatch_event_target_id`, which
  the aws-eventbridge component wires to its log group). It is a map, as in
  terraform-aws-modules/eventbridge, and adds input, dead-letter and retry
  settings, `ecs_target`/`batch_target` and the Lambda permission.
- The `aws_cloudwatch_log_resource_policy` is resource-scoped
  (`resource_arn = aws_cloudwatch_log_group.this[0].arn`, provider >= 6.36),
  not account-scoped (`policy_name`) as in Cloud Posse. Account-scoped
  policies are capped at 10 per region, shared with every other component and
  service in the account; a resource-scoped policy attaches to this log group
  alone and consumes none of that quota. It also carries an
  `aws:SourceAccount` condition Cloud Posse's policy does not have.
- Validations Cloud Posse does not have: the key ARN, the pattern is a
  non-empty object, a schedule is `cron(...)`/`rate(...)` on the default
  bus, the retention is one CloudWatch accepts, an archive needs
  a created bus, the DLQ ARN, the targets (count, IDs, ARNs, role use, input,
  standard dead-letter queue, retry ranges, FIFO message group, ECS/Batch
  settings), and preconditions that the archive name
  (`<Environment>-<name>`) is 48 characters or fewer and a Lambda permission
  statement ID 100 or fewer.

## Tests

`tests/eventbridge.tftest.hcl` runs against a mock provider (no credentials):

```
cd components/terraform/eventbridge && terraform init -backend=false && terraform test
```

## Usage

```
atmos terraform plan <instance> -s <stack>   # after adding an instance
```
