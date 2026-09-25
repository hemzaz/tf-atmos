# stepfunctions

One AWS Step Functions state machine per instance, modelled on Cloud Posse's
[aws-step-functions](https://github.com/cloudposse-terraform-components/aws-step-functions)
component (which wraps
[cloudposse/terraform-aws-step-functions](https://github.com/cloudposse/terraform-aws-step-functions)).
The state machine is encrypted with a customer managed KMS key, always logs to
a CloudWatch log group under `/aws/vendedlogs/states/` (the prefix AWS
requires for Step Functions log delivery), and its own execution role is
created here, trusted by `states.amazonaws.com` and scoped to this state
machine alone.

## Deployed instances

`stepfunctions/order-fulfilment` in `templates/stacks/serverless-stack.yaml`
(a template, not a deployed stack). The abstract base `stepfunctions/defaults`
(`stacks/catalog/stepfunctions/defaults.yaml`) wires the key from `kms/main`;
instances inherit it and set `name`, `definition` and, as needed,
`iam_policies`.

## Inputs / outputs

| Key | Notes |
|---|---|
| `region`, `tags`, `name`, `kms_key_arn` (required) | `tags` must include a non-empty `Environment`; the state machine, its execution role (`<Environment>-<name>-role`) and log group are all `<Environment>-<name>`-based. The key must be a KMS key ARN |
| `type` (`STANDARD`) | `STANDARD` or `EXPRESS` |
| `definition` (required) | Amazon States Language, as an object; the component `jsonencode`s it. Put ARNs a Task calls (a Lambda function, an SNS topic, ...) in it via `!terraform.state` so they never go stale |
| `logging_configuration` (`{}` → `level = "ALL"`, `include_execution_data = true`) | `level`: `ALL`, `ERROR`, `FATAL` or `OFF`. The log group is always created (`log_group_name` is never null); a non-`OFF` level attaches the execution role's log-delivery permissions and points the state machine at it. Defaults to full execution history logging (`ALL`, with Task input/output payloads included); `OFF` stops the state machine writing to it. Set `include_execution_data` to `false` for workflows whose Task input/output may carry sensitive data |
| `tracing_enabled` (`true`) | Enables AWS X-Ray tracing and attaches the execution role's X-Ray write permissions this requires. Defaults to `true` |
| `log_retention_days` (`90`) | CloudWatch Logs retention on the state machine's log group; any value CloudWatch Logs supports |
| `iam_policies` (`[]`) | list of `{sid, effect ("Allow"), actions, resources}`, merged into one inline policy on the execution role. CP-style statements, but identity-based: no `principals` (the role is fixed). Only for what a Task calls directly (`lambda:InvokeFunction` on a function it invokes, `sns:Publish` on a topic it publishes to, ...); a Task reaching another service through *that service's* resource policy (an SQS queue, another state machine started by EventBridge, ...) needs no statement here |
| `events_role_enabled` (`false`) | Creates an IAM role trusted by `events.amazonaws.com`, allowed `states:StartExecution` on this state machine only, output as `events_role_arn`, for use as an `eventbridge` instance's `targets.<id>.role_arn` |
| `enabled` (`true`) | `false` creates nothing |
| out: `state_machine_arn`, `state_machine_name`, `role_arn`, `log_group_name` | Always set when enabled |
| out: `events_role_arn` | Set only when `events_role_enabled`; null otherwise |

## Dependencies / gotchas

- **Key policy.** The log group encrypts with the key as `logs.<region>.amazonaws.com`,
  a service principal kms/main's root-account statement does not reach.
  kms/main's `allow_cloudwatch_logs` (on in every stack) covers it; it is not
  scoped to a log group name pattern, so no change was needed there for the
  `/aws/vendedlogs/states/` prefix.
- **Execution role trust.** Scoped by `aws:SourceAccount` and `aws:SourceArn`
  to this state machine's own ARN, which is deterministic from
  `region`/account/`name` and so knowable before the state machine exists (no
  create-before-create cycle).
- **EventBridge target.** This repo's `eventbridge` component's `targets`
  requires `role_arn` for a Step Functions target (states is not one of the
  services EventBridge reaches through a resource policy). `events_role_enabled`
  creates that role here, since the consuming `eventbridge` instance has no way
  to create a role scoped to a machine it does not own; wire it as
  `targets.<id>.role_arn: !terraform.state stepfunctions/<name> .events_role_arn`.
- A Task invoking a Lambda function still needs `lambda:InvokeFunction` in
  `iam_policies` even though EventBridge grants a *rule* that permission
  separately (`aws_lambda_permission`, in the `eventbridge` component): the
  state machine calls Lambda directly, as its execution role, not through
  EventBridge.

## Differences from Cloud Posse

- Plain resources instead of the `cloudposse/terraform-aws-step-functions`
  module; no `context.tf`/null-label, names come from `tags.Environment` and
  `default_tags` carries the tags.
- Creates and owns the execution role (scoped trust policy, log-delivery and
  X-Ray permissions, `iam_policies`) instead of taking an existing
  `service_integrations`/role input.
- Always creates the CloudWatch log group and always logs to it once a level
  is set; Cloud Posse's equivalent (`logging_configuration`) is closer to this
  but the trust/log-delivery wiring here is our own.
- Adds `encryption_configuration` (`CUSTOMER_MANAGED_KMS_KEY`, `kms_key_arn`),
  a state-machine feature that postdates Cloud Posse's component.
- Adds `events_role_enabled`/`events_role_arn`, which Cloud Posse's component
  has no equivalent for (it assumes the caller already has an invoking role).
- Validations Cloud Posse does not have: the key ARN, `type`, a non-empty
  `definition`, the logging level, and `iam_policies` (effect, non-empty
  actions/resources, no wildcard `Allow` action).

## Tests

`tests/stepfunctions.tftest.hcl` runs offline against the real provider with
dummy credentials:

```
cd components/terraform/stepfunctions && terraform init -backend=false && terraform test
```

## Usage

```yaml
components:
  terraform:
    stepfunctions/order-fulfilment:
      metadata:
        component: stepfunctions
        inherits: [stepfunctions/defaults]
      vars:
        name: order-fulfilment
        logging_configuration:
          level: ERROR
        definition:
          Comment: "Order fulfilment workflow"
          StartAt: ProcessOrder
          States:
            ProcessOrder:
              Type: Task
              Resource: !terraform.state lambda/order-processor .function_arn
              Next: NotifyCustomer
            NotifyCustomer:
              Type: Task
              Resource: "arn:aws:states:::sns:publish"
              Parameters:
                TopicArn: !terraform.state sns/notifications .sns_topic_arn
                Message.$: "$.confirmation"
              End: true
        iam_policies:
          - sid: InvokeOrderProcessor
            actions: ["lambda:InvokeFunction"]
            resources:
              - !terraform.state lambda/order-processor .function_arn
          - sid: PublishNotifications
            actions: ["sns:Publish"]
            resources:
              - !terraform.state sns/notifications .sns_topic_arn
      dependencies:
        components:
          - component: kms/main
          - component: lambda/order-processor
          - component: sns/notifications
```

```
atmos terraform plan stepfunctions/order-fulfilment -s <stack>
```
