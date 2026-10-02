# eventbridge

One EventBridge rule per instance (event pattern or `schedule_expression`) that always delivers to
its own CloudWatch log group, plus up to four further `targets`, and optionally a custom event bus
with an archive and dead-letter queue. Modelled on Cloud Posse `aws-eventbridge` (same inputs and
outputs); log group, bus and archive are encrypted with a customer managed key.

## Wiring

- No instance in the fnx stacks. `eventbridge/defaults` reads `kms/main .key_arn`; the
  `batch-processing`, `data-pipeline` and `microservices-platform` catalog templates and
  `templates/stacks/serverless-stack.yaml` configure rules.
- Other instances put their rules on a created bus through its `event_bus_name` output.
- Deploys in the `deploy-full-stack` services layer, after the state machines (platform), Batch
  queues and Lambdas (compute) and queues (storage) it targets. Rules reading a bus instance's
  state share that layer with it, so a stack with both needs them split by `.atmos_component`.

## Notes

- `kms/main` needs `allow_cloudwatch_logs` and `allow_eventbridge` (on in `kms/defaults`), or apply
  fails on the log group.
- Lambda targets get an `aws_lambda_permission` from this component. It lives in this state: if the
  function is replaced, re-apply this instance.
- SQS/SNS targets, a target's `dead_letter_config` and `event_bus_dlq_arn` need the queue's own
  policy to allow `events.amazonaws.com` with `aws:SourceArn` = the rule (or bus) ARN. Rule ARNs
  depend only on names, so queues can be applied first.
- `role_arn` is required for Step Functions, Kinesis, Firehose, ECS, Batch and EventBridge targets
  and rejected for Lambda, SQS, SNS and Logs. This component creates no such role (`stepfunctions`
  and `batch` can, via `events_role_enabled`).
- Schedules only run on the default bus, so `schedule_expression` rejects a custom bus.
- A CMK-encrypted bus should set `event_bus_dlq_arn`; schema discovery is unavailable on it.
- The log resource policy is resource-scoped (not the 10-per-region account policies).
- The archive name `<Environment>-<name>` must be 48 characters or fewer (precondition).
