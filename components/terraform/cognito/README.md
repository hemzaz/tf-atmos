# cognito

One Cognito user pool, an app client per `clients` entry, and an optional hosted-UI domain. It
gives `apigateway` a real pool for `COGNITO_USER_POOLS` authorization.

## Wiring

- Instance: `cognito/main` in the three AWS stacks and `fnx-local-sandbox` (applied for real by
  `atmos workflow sandbox`). Dev disables deletion protection; prod sets `mfa_configuration: ON`
  and 30-minute access tokens.
- Used by: `apigateway/main` and `apigateway/data` (`.user_pool_arn`).

## Notes

- `username_attributes`, `auto_verified_attributes` and a client's `generate_secret` are
  immutable: changing them replaces the pool (every user is lost) or the client.
- `advanced_security_mode` defaults to `ENFORCED`, billed per monthly active user.
- Self-signup is off (`allow_admin_create_user_only = true`), `prevent_user_existence_errors` is
  always on, and `ALLOW_USER_PASSWORD_AUTH` is rejected (use SRP).
- Browser and mobile clients must set `generate_secret: false`.
