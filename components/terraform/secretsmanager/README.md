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
  also written through `secret_string_wo`. A JSON value is stored as written, so ESO property
  lookups work. Supply it per instance, as `TF_VAR_secret_data` in that instance's Atmos `env:`
  section, not under `vars`: Terraform needs an ephemeral value set at plan again when a saved
  plan is applied, and `deploy --from-plan` applies the planfile without the varfile.
  - A real secret: `env: { TF_VAR_secret_data: !env FNX_<STACK>_<INSTANCE>_SECRET_DATA }`, the
    variable holding the JSON map, set in the operator's shell or as a CI secret. Atmos 1.229
    evaluates `!env` inside `env:` for terraform commands.
  - Never export a global `TF_VAR_secret_data`: the CD and drift loops would hand it to every
    secretsmanager instance, and an instance without those `static_value` keys rejects it. A
    stack's `env:` entry also overrides the process environment for its instance.
  - plan-sweep (`--process-functions=false`) cannot resolve `!env` and drops the value, so an
    instance fed that way fails the sweep on "needs a non-empty value"; the dropped name is listed.
  - Atmos debug/trace logging can print the component environment: don't run such an instance with
    `--logs-level=Debug` or `Trace`.
  - The weak-pattern check reads a JSON object's top-level values only. A nested object or list
    value is checked as its re-encoded JSON, key names included, so a key such as `db_password` inside
    one can be reported as a weak pattern: keep `secret_data` JSON flat.
- Neither: the secret is created empty, for an operator or application to fill.
- `secrets[*].secret_data` was removed and is rejected.

## Rotation

- A value is sent only when the version resource is created. Changing the secret's
  `secret_string_version` REPLACES that resource (ForceNew): a new `PutSecretValue` that becomes
  `AWSCURRENT`. To rotate a generated value (or push a changed `secret_data` value), bump it,
  e.g. `1` -> `2`, plan and apply.
- For a secret a Lambda rotates (`rotation_lambda_arn` + `rotation_automatically`, or
  `rotation_managed_externally: true`), never bump it: that puts a Terraform value back as
  `AWSCURRENT`. Rotate with `aws secretsmanager rotate-secret --secret-id <arn>` instead.
- If Secrets Manager purges the Terraform-created version (it deletes unlabelled versions beyond
  ~100), the next apply re-creates it and writes a Terraform value over the Lambda-rotated one.
  For Lambda-rotated secrets, watch the version count.
- Enabling rotation calls `RotateSecret`, which invokes the function's `testSecret` step even with
  `rotate_immediately = false`, so the function must already exist and allow
  `secretsmanager.amazonaws.com`.
- For a rotation Lambda that reads this secret's ARN via `!terraform.state`, set
  `rotation_managed_externally: true` here and configure rotation in the `lambda` instance
  (`rotation_secret_arn`, `rotation_days`); setting it here creates an ordering cycle.

## Notes

- Nothing is created when `enabled` or `secrets_enabled` is `false`.
- `secrets` is a typed object map: Terraform drops an unknown attribute silently, so lint
  (`workflows/scripts/common/check-secret-attributes.py`) fails any stack entry key that
  `variables.tf` does not declare.
