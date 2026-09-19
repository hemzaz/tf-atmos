# lambda

Generic Lambda function component: IAM role + custom policy, CloudWatch log
group, optional VPC security group, the `aws_lambda_function` itself (Zip or
Image package), permissions for API Gateway/S3/CloudWatch/SNS/EventBridge
triggers, async event-invoke config, provisioned concurrency, an alias,
CloudWatch alarms (duration/error rate/throttles), and an optional EventBridge schedule rule.

## Deployed instances

Not currently deployed in any of the 3 real stacks (fnx-dev-testenv-01,
fnx-staging-staging-01, fnx-prod-production) — zero instances. Add a
`lambda/<name>` entry to a stack's `components.terraform` before this applies.

## Inputs / outputs

| Key | Notes |
|---|---|
| `function_name`, `handler` (required, no default) | — |
| `runtime` | default `nodejs22.x` |
| `filename` / `s3_bucket`+`s3_key` | package source; no cross-validation that one is set |
| `subnet_ids` set → requires `vpc_endpoint_prefix_list_ids` | validated |
| `package_type` | `Zip` or `Image` only (validated) |
| `architectures` | `x86_64`/`arm64` only (validated) |
| `tags` | plain `map(string)`, default `{}` — no required-key validation (unlike other components here) |
| out: `function_arn`, `function_invoke_arn`, `role_arn`, `alias_arn` | — |

## Dependencies / gotchas

- No `dependencies.components` entries exist anywhere (component is unused).
- Deploying into a VPC (`subnet_ids` non-empty) fails validation unless `vpc_endpoint_prefix_list_ids` is also set — needed for S3 access from inside the VPC.
- `kms_key_arn` must match `^arn:aws:kms:` or be null (validated).
- No required `Environment` tag check here, unlike `backup`/`cost-optimization`.

## Usage

```
atmos terraform plan lambda -s fnx-dev-testenv-01
```
(after adding a `lambda` component entry to that stack).
