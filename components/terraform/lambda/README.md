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
| `filename` / `s3_bucket`+`s3_key` / `source_dir` | package source; **exactly one is required** for a Zip package (validated by a precondition on `aws_lambda_function.main`). `source_dir` zips a directory under this component itself (e.g. `functions/redis-auth-rotation`) via `archive_file`, for small in-repo sources; `filename`/`s3_bucket`+`s3_key` still suit an externally-built package (e.g. `welcome-email`, uploaded by CI). `image_uri` has no variable, so `package_type = "Image"` is unusable |
| `vpc_endpoint_prefix_list_ids` | optional override; empty resolves the region's AWS-managed S3 prefix list |
| `package_type` | `Zip` or `Image` only (validated) |
| `architectures` | `x86_64`/`arm64` only (validated) |
| `configure_event_invoke`, `on_success_destination`, `on_failure_destination`, `dead_letter_target_arn`, `delivery_kms_key_arn` | asynchronous-invocation destinations and the dead-letter target. For each SQS queue / SNS topic named there the execution role gets `sqs:SendMessage` / `sns:Publish` (policy `<Environment>-<function_name>-delivery`), and `kms:GenerateDataKey`/`kms:Decrypt` on `delivery_kms_key_arn` when the queue or topic is encrypted with a customer managed key. Other destination types (Lambda, EventBridge) still need `custom_policy` |
| `secretsmanager_source_arn` | adds a resource-based permission letting `secretsmanager.amazonaws.com` invoke this function as a rotation function, scoped by that secret's ARN and this account. Pair with the secretsmanager component's `rotation_lambda_arn` set to this function's own ARN |
| `tags` | required; must include a non-empty `Environment` (validated), used in every resource name |
| out: `function_arn`, `function_invoke_arn`, `role_arn`, `security_group_id`, `alias_arn` | — |

## Dependencies / gotchas

- Used by 6 instances across dev, staging and prod, plus `lambda/main` in the sandbox — which is
  the only place this component actually executes. Every real instance was uncreatable until
  2026-09 for want of a package source; the sandbox is what caught it. Two more instances,
  `microservices/lambda/redis-auth-rotation` and `microservices/lambda/jwt-secret-rotation` in
  `stacks/catalog/templates/microservices-platform.yaml`, use `source_dir` instead and are not
  deployed into any real stack either (that template is not imported by any of the 3).
- Deploying into a VPC (`subnet_ids` non-empty) resolves the region's AWS-managed S3 prefix list (`com.amazonaws.<region>.s3`) for egress, so no stack has to hardcode a region-specific `pl-*`. Until 2026-09 this was a hard validation instead, and it made every VPC lambda in every stack fail at plan. Set `vpc_endpoint_prefix_list_ids` explicitly to confine egress to real interface endpoints. Egress is never `0.0.0.0/0` either way.
- `kms_key_arn` must match `^arn:aws:kms:` or be null (validated).
- No required `Environment` tag check here, unlike `backup`/`cost-optimization`.
- `source_dir` is resolved relative to `path.module` (this component's own directory), not the
  calling stack -- the function source lives under `functions/<name>/` inside this component,
  mirroring how `cost-optimization` keeps its own Lambda sources under its `lambda/` directory.
  The zip is written to `.archives/<function_name>.zip` under this component (gitignored); a
  second instance with the same `function_name` in the same `terraform apply` run would collide
  on that path, so keep `function_name` unique per instance as it already must be for the
  function itself.

## Usage

```
atmos terraform plan lambda -s fnx-dev-testenv-01
```
(after adding a `lambda` component entry to that stack).
