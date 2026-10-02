# stepfunctions

One Step Functions state machine per instance, encrypted with a customer managed key, logging to a
`/aws/vendedlogs/states/` log group, with its own execution role trusted by `states.amazonaws.com`
and scoped to this machine. Modelled on Cloud Posse `aws-step-functions`.

## Wiring

- No instance in the fnx stacks. `stepfunctions/defaults` reads `kms/main .key_arn`;
  `templates/stacks/serverless-stack.yaml` creates `stepfunctions/order-fulfilment`, whose
  `definition` and `iam_policies` read Lambda and SNS ARNs through `!terraform.state`. The
  `batch-processing` catalog template creates `batch-processing/stepfunctions/data-pipeline` and
  `/parallel-processor`, which submit `batch` jobs (`.sync`).
- Deploys in the `deploy-full-stack` platform layer, after compute (the batch and lambda state its
  definitions read) and before the `eventbridge` rules (services) that start it.
- `events_role_arn` (with `events_role_enabled`) is the `role_arn` an `eventbridge` target needs to
  start this machine.

## Notes

- A CMK-encrypted, logging machine needs three key grants: `kms/main`'s `allow_cloudwatch_logs` and
  `allow_log_delivery` (on in `kms/defaults`), and the execution role's own grant, which this
  component adds.
- A Task calling another CMK-encrypted resource (for example `sns:Publish` to an encrypted topic)
  needs its own KMS statement in `iam_policies`, scoped with `conditions` to that resource's
  encryption context.
- A Task invoking Lambda needs `lambda:InvokeFunction` in `iam_policies`; the machine calls Lambda as
  its own role.
- Logging defaults to `ALL` with execution data and X-Ray on; set `include_execution_data = false`
  for workflows whose payloads may be sensitive.
- The trust policy uses the machine's ARN built from its name, so there is no create cycle.
