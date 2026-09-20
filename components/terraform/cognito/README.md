# cognito

Cognito user pool and app clients for API authorization.

Creates one user pool, an app client per entry in `clients`, and optionally a
hosted-UI domain. It exists so `apigateway` has a real pool to point
`cognito_user_pool_arns` at: a method declaring
`authorization = "COGNITO_USER_POOLS"` fails at apply when no pool is wired to
it.

## Deployed as

| Instance | Stack | Notable settings |
|---|---|---|
| `cognito/main` | `fnx-dev-testenv-01` | `deletion_protection: false`, so a torn-down env leaves nothing behind |
| `cognito/main` | `fnx-staging-staging-01` | catalog defaults |
| `cognito/main` | `fnx-prod-production` | `mfa_configuration: ON`, 30-minute access tokens |

| Input | Notes |
|---|---|
| `region`, `name_prefix`, `enabled`, `tags` | House-rule inputs; `tags` must carry a non-empty `Environment` |
| `username_attributes` / `auto_verified_attributes` | **Immutable.** Changing either replaces the pool and every user in it |
| `password_minimum_length` | Default 14. Upper, lower, digit and symbol are always required |
| `mfa_configuration` | `OFF`, `OPTIONAL` (default) or `ON`. Software-token MFA turns on whenever this is not `OFF` |
| `advanced_security_mode` | `OFF`, `AUDIT` or `ENFORCED` (default). **Billed per monthly active user** above `OFF` |
| `allow_admin_create_user_only` | Default `true` — public self-signup is refused |
| `deletion_protection` | Default `true` |
| `domain_prefix` | Empty means no hosted UI, which an API-authorizer-only pool does not need |
| `clients` | App clients keyed by name; the key is appended to `name_prefix` |

Outputs: `user_pool_id`, `user_pool_arn`, `user_pool_endpoint`, `client_ids`,
`hosted_ui_domain`, plus `name_prefix` and `enabled`.

## Dependencies / gotchas

- **`username_attributes` and `auto_verified_attributes` cannot be changed.**
  Cognito rejects the update, so Terraform replaces the pool — destroying every
  user in it. Treat both as decided at creation time.
- **`advanced_security_mode` costs money.** `ENFORCED` is the default here
  because the pool guards an API, but it is billed per monthly active user. Set
  it to `OFF` in throwaway environments if the bill matters more than the
  threat detection.
- **`generate_secret` is immutable too**, and only correct for confidential
  clients. A browser or mobile client cannot keep a secret and must set
  `generate_secret: false`.
- `ALLOW_USER_PASSWORD_AUTH` is rejected by a validation block: it sends the
  raw password to the API. Use `ALLOW_USER_SRP_AUTH`.
- `prevent_user_existence_errors` is always `ENABLED`. Without it a caller can
  tell a wrong password from an unknown user and enumerate the directory.
- **Not exercised by the sandbox.** `atmos workflow sandbox` applies `kms`,
  `vpc`, `dns`, `secretsmanager` and `ecs` only; there is no cognito instance
  in `fnx-local-sandbox`. Covered by `terraform validate`, tflint, the scanners
  and a variable-validation harness, but nothing has executed it against an API.
- The pool's ARN reaches `apigateway` through
  `!terraform.state cognito/main .user_pool_arn`, so the API Gateway instances
  declare `cognito/main` in `dependencies.components`.

## Usage

```
atmos terraform plan cognito/main -s fnx-dev-testenv-01
```
