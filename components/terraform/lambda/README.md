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
| `filename` / `s3_bucket`+`s3_key` | package source; **one is required** — the provider rejects the function at apply with `one of filename,image_uri,s3_bucket must be specified`. Nothing here validates it, and no static gate catches it. `image_uri` has no variable, so `package_type = "Image"` is unusable |
| `vpc_endpoint_prefix_list_ids` | optional override; empty resolves the region's AWS-managed S3 prefix list |
| `package_type` | `Zip` or `Image` only (validated) |
| `architectures` | `x86_64`/`arm64` only (validated) |
| `tags` | required; must include a non-empty `Environment` (validated), used in every resource name |
| out: `function_arn`, `function_invoke_arn`, `role_arn`, `alias_arn` | — |

## Dependencies / gotchas

- Used by 6 instances across dev, staging and prod, plus `lambda/main` in the sandbox — which is
  the only place this component actually executes. Every real instance was uncreatable until
  2026-09 for want of a package source; the sandbox is what caught it.
- Deploying into a VPC (`subnet_ids` non-empty) resolves the region's AWS-managed S3 prefix list (`com.amazonaws.<region>.s3`) for egress, so no stack has to hardcode a region-specific `pl-*`. Until 2026-09 this was a hard validation instead, and it made every VPC lambda in every stack fail at plan. Set `vpc_endpoint_prefix_list_ids` explicitly to confine egress to real interface endpoints. Egress is never `0.0.0.0/0` either way.
- `kms_key_arn` must match `^arn:aws:kms:` or be null (validated).
- No required `Environment` tag check here, unlike `backup`/`cost-optimization`.

## Usage

```
atmos terraform plan lambda -s fnx-dev-testenv-01
```
(after adding a `lambda` component entry to that stack).
