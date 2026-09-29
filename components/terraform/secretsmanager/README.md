# secretsmanager

One Secrets Manager secret and version per `secrets` entry, with optional generated password,
resource policy (`policies/*.json.tpl`) and rotation.

## Wiring

- Instances: `secretsmanager/app` in the three AWS stacks and `fnx-local-sandbox`;
  `secretsmanager/infra` in the three AWS stacks. Both read `kms/main .key_arn`.
  `secretsmanager/api`, `/app-db` and `/infra-defaults` in the catalog are abstract.
- Used by: nothing via state in the real stacks (consumers read secrets at runtime).
  `secret_access_policy` is an IAM policy document meant for a rotation Lambda's
  `custom_policy`, as in the `microservices-platform` template.

## Notes

- Nothing is created when `enabled` or `secrets_enabled` is `false`.
- Catalog connection-string secrets leave `secret_data: null` for per-stack overrides.
- Once rotation is on (`rotation_lambda_arn` + `rotation_automatically`, or
  `rotation_managed_externally: true`), the version ignores `secret_string` changes, and
  `generated_passwords` / `secret_values` keep the original value forever. Never feed them to
  another resource's credential once rotation is live.
- Enabling rotation calls `RotateSecret`, which invokes the function's `testSecret` step even with
  `rotate_immediately = false`, so the function must already exist and allow
  `secretsmanager.amazonaws.com`.
- For a rotation Lambda that reads this secret's ARN via `!terraform.state`, set
  `rotation_managed_externally: true` here and configure rotation in the `lambda` instance
  (`rotation_secret_arn`, `rotation_days`); setting it here creates an ordering cycle.
