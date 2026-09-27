# secretsmanager

Creates one or more `aws_secretsmanager_secret` + version per entry in the
`secrets` map, with optional `random_password` generation, optional resource
policy (from templates in `policies/*.json.tpl`) and optional automatic
rotation (`aws_secretsmanager_secret_rotation`).

## Deployed instances

Real instances in all 3 stacks (fnx-dev-testenv-01, fnx-staging-staging-01,
fnx-prod-production): `secretsmanager/app` and `secretsmanager/infra`.
Additional catalog entries — `secretsmanager/api`, `secretsmanager/app-db`,
`secretsmanager/defaults`, `secretsmanager/infra-defaults` — exist in every
stack too but are **abstract** (`type: abstract`), inherited-from templates
only, not deployed directly. `microservices/secrets` in
`stacks/catalog/templates/microservices-platform.yaml` is the first instance
with rotation actually wired (its `redis` and `jwt_signing` entries); that
template is not imported by any of the 3 real stacks either.

## Inputs / outputs

| Key | Notes |
|---|---|
| `context_name` (required) | must be non-empty (validated) |
| `secrets` (map) | per-secret `name`, `description`, `path`, `generate_random_password` or `secret_data`, `random_password_override_special`, `rotation_lambda_arn`/`rotation_automatically`/`rotation_days`/`rotate_immediately`, `rotation_managed_externally` |
| `default_rotation_days` | 1-365 (validated), default 30 |
| `default_rotation_automatically` | default `false` |
| `default_rotate_immediately` | default `false` (opposite of the AWS provider's own default of `true`) -- see the gotcha below |
| `default_recovery_window_in_days` | 0-30 (validated), default 30 |
| `random_password_length` | >= 8 (validated), default 32 |
| out: `secret_arns`, `secret_ids`, `generated_passwords`, `rotation_enabled_secrets`, `secret_access_policy` | — |

## Dependencies / gotchas

- No `dependencies.components` entries and no other stack references its outputs via `!terraform.state` — consumers read secrets at runtime, not via Terraform state chaining. `secret_access_policy` is the one exception: it is a ready-made IAM policy document meant to be wired into a rotation Lambda's `custom_policy` via `!terraform.state`, mirroring the `kinesis` component's `reader_policy`/`writer_policy` pattern.
- `secrets_enabled = false` (or `enabled = false`) short-circuits secret creation entirely — check both vars before assuming a catalog entry creates resources.
- Catalog defaults leave `secret_data: null` for connection-string secrets, expecting per-environment overrides — an unoverridden entry yields a null value.
- Once a secret's rotation is enabled (`rotation_automatically` + `rotation_lambda_arn`, or `rotation_managed_externally: true`), `aws_secretsmanager_secret_version` for it (the `rotating` resource, not `this`) sets `lifecycle { ignore_changes = [secret_string] }`: after the initial create, the rotation Lambda's `finishSecret` step owns the real value in AWS, and this resource must stop fighting it for the value on every later apply. `generated_passwords` and `secret_values` still return only the ORIGINAL Terraform-generated value forever, for the same reason — never read them to configure another resource's credential (e.g. `elasticache`'s `auth_token`) once rotation is live.
- `rotate_immediately` defaults to `false`, the opposite of the AWS provider's own default: even at `false`, Secrets Manager's `RotateSecret` API (which `aws_secretsmanager_secret_rotation` calls under the hood) tests the rotation configuration — running `createSecret`/`setSecret`/`testSecret` against a temporary `AWSPENDING` version — so `rotation_lambda_arn` must already name a function that exists and is permitted to be invoked by `secretsmanager.amazonaws.com`, not merely exist as a string, before this component's own apply.
- **Do not** set `rotation_lambda_arn`/`rotation_automatically` here for a Lambda that itself reads this secret via `!terraform.state` (the common case — the Lambda needs the secret's own ARN to scope its `custom_policy`). That closes a `secrets -> lambda` ordering requirement this component cannot satisfy on its own first apply: the function does not exist yet when this component applies. Use `rotation_managed_externally: true` on the secret instead, and configure rotation from the **Lambda's own component instance** via the `lambda` component's `rotation_secret_arn`/`rotation_days` inputs — that instance already depends on this one (to read the secret's ARN), so by the time it applies, the function and its `secretsmanager.amazonaws.com` invoke permission (`secretsmanager_source_arn`) already exist, and `aws_secretsmanager_secret_rotation`'s own `RotateSecret` test succeeds. See `microservices-platform.yaml`'s `microservices/secrets` and `microservices/lambda/redis-auth-rotation`/`jwt-secret-rotation` for the wiring.

## Usage

```
atmos terraform plan secretsmanager/app -s fnx-dev-testenv-01
atmos terraform plan secretsmanager/infra -s fnx-prod-production
```
