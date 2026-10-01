# secretsmanager

One Secrets Manager secret per `secrets` entry, with an optional value, resource policy
(`policies/*.json.tpl`) and rotation. No secret value is ever in plan, state or outputs.

## Wiring

- Instances: `secretsmanager/app` in the three AWS stacks and `fnx-local-sandbox`;
  `secretsmanager/infra` in the three AWS stacks. Both read `kms/main .key_arn`.
  `secretsmanager/api`, `/app-db` and `/infra-defaults` in the catalog are abstract.
- Used by: nothing via state in the real stacks. Consumers read values at runtime (ESO, the
  application) by `secret_arns` / `secret_names`; no output carries a value.
  `secret_access_policy` is an IAM policy document meant for a rotation Lambda's
  `custom_policy`, as in the `microservices-platform` template.

## Values

- `generate_random_password: true`: an ephemeral `random_password` (per-secret `password_length`
  and `random_password_override_special`), written through `secret_string_wo`, as elasticache's
  AUTH token. Cloud Posse keeps a stored `random_password`; this component does not.
- `static_value: true`: the value comes from the ephemeral, sensitive `secret_data` map (same key),
  also written through `secret_string_wo`. Supply it as `TF_VAR_secret_data` (the instance's Atmos
  `env:` section, or the shell/CI for a real secret), not under `vars`: Terraform needs an
  ephemeral value set at plan again when a saved plan is applied, and `deploy --from-plan` applies
  the planfile without the varfile. A JSON value is stored as written, so ESO property lookups work.
- Neither: the secret is created empty, for an operator or application to fill.
- `secrets[*].secret_data` was removed and is rejected.

## Rotation

- A value is sent on the version's create and, after that, only when the secret's
  `secret_string_version` changes. To rotate a generated value (or push a changed `secret_data`
  value), bump it, e.g. `1` -> `2`, plan and apply.
- For a secret a Lambda rotates (`rotation_lambda_arn` + `rotation_automatically`, or
  `rotation_managed_externally: true`), never bump it: that puts a Terraform value back as
  `AWSCURRENT`. Rotate with `aws secretsmanager rotate-secret --secret-id <arn>` instead.
- Enabling rotation calls `RotateSecret`, which invokes the function's `testSecret` step even with
  `rotate_immediately = false`, so the function must already exist and allow
  `secretsmanager.amazonaws.com`.
- For a rotation Lambda that reads this secret's ARN via `!terraform.state`, set
  `rotation_managed_externally: true` here and configure rotation in the `lambda` instance
  (`rotation_secret_arn`, `rotation_days`); setting it here creates an ordering cycle.

## Notes

- Nothing is created when `enabled` or `secrets_enabled` is `false`.
- `secrets` is a typed object map: an unknown attribute is dropped silently, so check the
  spelling against `variables.tf`.
