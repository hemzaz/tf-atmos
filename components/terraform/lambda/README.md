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
| `filename` / `s3_bucket`+`s3_key` / `source_dir` | package source; **exactly one is required** for a Zip package (validated by a precondition on `aws_lambda_function.main`). `source_dir` zips a directory under this component itself (e.g. `functions/redis-auth-rotation`) via `archive_file`, for small in-repo sources -- the equivalent of Cloud Posse's [`cloudposse-terraform-components/aws-lambda`](https://github.com/cloudposse-terraform-components/aws-lambda)'s own `zip` input (`{enabled, input_dir, output}`, also backed by `archive_file`); `filename`/`s3_bucket`+`s3_key` still suit an externally-built package (e.g. `welcome-email`, uploaded by CI). `image_uri` has no variable, so `package_type = "Image"` is unusable |
| `vpc_endpoint_prefix_list_ids` | optional override; empty resolves the region's AWS-managed S3 prefix list |
| `package_type` | `Zip` or `Image` only (validated) |
| `architectures` | `x86_64`/`arm64` only (validated) |
| `configure_event_invoke`, `on_success_destination`, `on_failure_destination`, `dead_letter_target_arn`, `delivery_kms_key_arn` | asynchronous-invocation destinations and the dead-letter target. For each SQS queue / SNS topic named there the execution role gets `sqs:SendMessage` / `sns:Publish` (policy `<Environment>-<function_name>-delivery`), and `kms:GenerateDataKey`/`kms:Decrypt` on `delivery_kms_key_arn` when the queue or topic is encrypted with a customer managed key. Other destination types (Lambda, EventBridge) still need `custom_policy` |
| `secretsmanager_source_arn` | adds a resource-based permission letting `secretsmanager.amazonaws.com` invoke this function as a rotation function, scoped by that secret's ARN and this account |
| `rotation_secret_arn`, `rotation_days` (30), `rotate_immediately` (`false`) | configures `aws_secretsmanager_secret_rotation` on that secret from **this** component instance (not the secretsmanager component's own `rotation_lambda_arn`), `depends_on` this function's own invoke permission AND its IAM role policies -- see "Rotation functions" below for why, and for when `rotate_immediately` needs to be `true` instead |
| `additional_security_group_ids` | extra security group IDs attached to this function's VPC ENI alongside the one this component creates itself -- e.g. a cache's client security group, so that cache's own security group never has to read this function's security group back |
| `kms_key_arn` | encrypts this function's environment variables with a customer managed key; the execution role also gets a `kms:Decrypt` grant scoped to it and to `kms:EncryptionContext:aws:lambda:FunctionArn` = this function's own ARN (the AWS-owned default key needs no such grant) |
| `tags` | required; must include a non-empty `Environment` (validated), used in every resource name |
| out: `function_arn`, `function_invoke_arn`, `role_arn`, `security_group_id`, `alias_arn` | — |

## Rotation functions

Two instances of this component, `microservices/lambda/redis-auth-rotation` and
`microservices/lambda/jwt-secret-rotation` in `stacks/catalog/templates/microservices-platform.yaml`,
are Secrets Manager rotation Lambdas for `microservices/secrets`' `redis` and `jwt_signing` entries.
Both set `secretsmanager_source_arn` (the invoke permission) and `rotation_secret_arn` (the rotation
configuration itself) to the SAME secret's ARN, and are packaged via `source_dir` (see
`functions/redis-auth-rotation` and `functions/jwt-secret-rotation`).

- **Rotation is configured here, not on the secretsmanager component.** A rotation Lambda that
  itself reads the secret it rotates (to scope its own `custom_policy` to that one secret) cannot
  have `aws_secretsmanager_secret_rotation` configured on the secretsmanager component instance,
  because Secrets Manager's `RotateSecret` API invokes the function -- at minimum running its
  `testSecret` step against a temporary `AWSPENDING` version it creates and then removes -- even when
  `rotate_immediately` is `false`, and on the secret's own first apply this function and its invoke
  permission do not exist yet. This Lambda instance already depends on the secret's own component
  instance, so by the time `rotation_secret_arn`'s resource applies HERE, the function, its permission
  and its IAM role policies already exist (`depends_on` covers all of them). The paired secretsmanager
  entry sets `rotation_managed_externally: true` instead of `rotation_lambda_arn`/
  `rotation_automatically`.
- **`rotate_immediately` and `setSecret`.** At `rotate_immediately = false`, only the `testSecret`
  step runs, against a temporary `AWSPENDING` version Secrets Manager manufactures itself for the
  test; `setSecret` -- the step that actually pushes a new value to whatever external system the
  function updates -- never runs, so this path never exercises that call. This does NOT mean a
  `testSecret` like `redis-auth-rotation`'s (which AUTHs against the replication group with the
  pending token) fails at `rotate_immediately = false`: AWS's own docs only say the manufactured
  `AWSPENDING` version is "created and then removed", but AWS's own reference templates only pass
  their equivalent test if it is a copy of `AWSCURRENT` -- i.e. the still-valid current token, which
  does AUTH successfully. `redis-auth-rotation` sets `rotate_immediately = true` in
  `microservices-platform.yaml` not to avoid a failure, but so every apply that (re)configures this
  resource performs and verifies a REAL rotation (a fresh token, pushed via `setSecret`, confirmed via
  `testSecret`) end to end, rather than a same-value round-trip that proves nothing. `jwt-secret-
  rotation` keeps the default `false`: its `testSecret` only confirms the `AWSPENDING` value is
  non-empty (`setSecret` is a no-op for it either way), and deliberately does NOT check the value's
  length, precisely because that value may be the copy-of-`AWSCURRENT` this test-only path supplies --
  see that function's own `test_secret` docstring.
  **Caution:** with `rotate_immediately = true`, ANY later change to this resource (e.g. a
  `rotation_days` edit, or a new `rotation_lambda_arn` from a function rename/replacement) re-invokes
  `RotateSecret` with `RotateImmediately = true`, triggering an unscheduled rotation at that
  `terraform apply` -- for `redis-auth-rotation`, an unscheduled AUTH token change on the replication
  group (two `ModifyReplicationGroup` calls). Plan for that before changing this resource's other
  arguments.
- **`redis-auth-rotation`**: environment variables `REPLICATION_GROUP_ID`, `REDIS_HOST`, `REDIS_PORT`
  (the ElastiCache replication group to modify and to AUTH-test against). Runs in the VPC's private
  subnets, with `additional_security_group_ids` set to the cache's `client_security_group_id` (egress
  to the cache port goes through `custom_egress_rules`' `security_groups`, scoped to the cache's own
  security group, not a CIDR). IAM (`custom_policy`) is the cache's `rotation_policy` output, which
  folds in the secret's own `secret_access_policy` -- `elasticache:ModifyReplicationGroup`/
  `DescribeReplicationGroups` on that one replication group, plus the secret's own read/write and KMS
  grants.
- **`jwt-secret-rotation`**: no VPC needed (nothing in a VPC to reach) and no dual-key/grace-period
  handling in this repo -- nothing here verifies a JWT. `setSecret` is a no-op (nothing outside
  Secrets Manager holds a copy of the signing key). **Any real JWT verifier for this secret must
  accept a token signed by either the `AWSCURRENT` or `AWSPREVIOUS` version for at least the token's
  own max lifetime after each rotation** (fetch both stages with `GetSecretValue` and try each, or
  version tokens with a `kid` claim naming which secret version signed them) -- otherwise every token
  issued in the `rotation_days` window before a rotation is rejected the moment it lands. See the
  function's own module docstring (`functions/jwt-secret-rotation/lambda_function.py`) for the full
  note.

## Dependencies / gotchas

- Used by 6 instances across dev, staging and prod, plus `lambda/main` in the sandbox — which is
  the only place this component actually executes. Every real instance was uncreatable until
  2026-09 for want of a package source; the sandbox is what caught it. Two more instances,
  `microservices/lambda/redis-auth-rotation` and `microservices/lambda/jwt-secret-rotation` in
  `stacks/catalog/templates/microservices-platform.yaml`, use `source_dir` instead and are not
  deployed into any real stack either (that template is not imported by any of the 3).
- Deploying into a VPC (`subnet_ids` non-empty) resolves the region's AWS-managed S3 prefix list (`com.amazonaws.<region>.s3`) for egress, so no stack has to hardcode a region-specific `pl-*`. Until 2026-09 this was a hard validation instead, and it made every VPC lambda in every stack fail at plan. Set `vpc_endpoint_prefix_list_ids` explicitly to confine egress to real interface endpoints. The component's own built-in egress rules are never `0.0.0.0/0` -- but `custom_egress_rules` can add broader egress when a stack needs it, e.g. `redis-auth-rotation`'s NAT-routed `0.0.0.0/0:443` rule to reach the Secrets Manager API (no VPC endpoint for it in this stack).
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
