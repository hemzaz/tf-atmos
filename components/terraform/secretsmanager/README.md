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
only, not deployed directly.

## Inputs / outputs

| Key | Notes |
|---|---|
| `context_name` (required) | must be non-empty (validated) |
| `secrets` (map) | per-secret `name`, `description`, `path`, `generate_random_password` or `secret_data` |
| `default_rotation_days` | 1-365 (validated), default 30 |
| `default_recovery_window_in_days` | 0-30 (validated), default 30 |
| `random_password_length` | >= 8 (validated), default 32 |
| out: `secret_arns`, `secret_ids`, `generated_passwords`, `rotation_enabled_secrets` | — |

## Dependencies / gotchas

- No `dependencies.components` entries and no other stack references its outputs via `!terraform.state` — consumers read secrets at runtime, not via Terraform state chaining.
- `secrets_enabled = false` (or `enabled = false`) short-circuits secret creation entirely — check both vars before assuming a catalog entry creates resources.
- Catalog defaults leave `secret_data: null` for connection-string secrets, expecting per-environment overrides — an unoverridden entry yields a null value.

## Usage

```
atmos terraform plan secretsmanager/app -s fnx-dev-testenv-01
atmos terraform plan secretsmanager/infra -s fnx-prod-production
```
