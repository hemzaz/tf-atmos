# cognito

One Cognito user pool, an app client per `clients` entry, OAuth resource servers
(`resource_servers`), custom string attributes (`string_schemas`), and an optional hosted-UI
domain. It gives `apigateway` a real pool for `COGNITO_USER_POOLS` authorization.
`resource_servers` and `string_schemas` take Cloud Posse `aws-cognito`'s names and shapes (typed;
its `schemas`/`number_schemas` are not ported).

## Wiring

- Instance: `cognito/main` in the AWS stacks and `fnx-ue1-local-sandbox` (applied for real by
  `atmos workflow sandbox`). Dev disables deletion protection; both prod pools inherit
  `cognito/prod` (`mfa_configuration: ON`, deletion protection) and set 30-minute access tokens.
  `fnx-ew1-prod`'s is the EU pool: its own users, no migration from or to a US pool.
- DR: `fnx-ue2-prod`'s pool has `lambda/cognito-user-migration` as its `user_migration` trigger,
  which checks users against `fnx-ue1-prod`'s pool through that pool's `dr-migration` client
  (`.user_pool_id`, `.user_pool_arn`, `.client_ids["dr-migration"]`); docs/OPERATIONS.md, "Auth
  during failover".
- Used by: `apigateway/main` and `apigateway/data` (`.user_pool_arn`), each region's own pool.

## Notes

- `username_attributes`, `auto_verified_attributes` and a client's `generate_secret` are
  immutable: changing them replaces the pool (every user is lost) or the client.
- Threat protection (`advanced_security_mode` `AUDIT`/`ENFORCED`) needs the PLUS feature plan
  (`user_pool_tier = "PLUS"`, validated). The component defaults to `OFF` and `ESSENTIALS`;
  `cognito/defaults` sets `ENFORCED` + `PLUS` for the AWS stacks. PLUS is billed per monthly
  active user with no free tier (ESSENTIALS has 10,000 free MAU).
- Self-signup is off (`allow_admin_create_user_only = true`), `prevent_user_existence_errors` is
  always on, and `ALLOW_USER_PASSWORD_AUTH` is rejected (use SRP).
- Browser and mobile clients must set `generate_secret: false`.
- A `client_credentials` client needs a confidential client (`generate_secret`), a
  `domain_prefix` (the token endpoint) and scopes from `resource_servers`, named
  `<identifier>/<scope_name>` in its `allowed_oauth_scopes`, and no other OAuth flow (all
  validated). Clients are created after the resource servers.
- `email_configuration` takes Cloud Posse `aws-cognito`'s keys as one typed object. The default,
  `COGNITO_DEFAULT`, sends through Cognito's own account, capped at about 50 emails a day per
  account: fine for dev, not for real sign-ups. `DEVELOPER` sends through the verified SES
  identity `source_arn` (validated), whose sending authorization policy must allow
  `cognito-idp.amazonaws.com`, and whose account must be out of the SES sandbox to reach
  unverified recipients. `""` counts as unset. `from_email_address` with `COGNITO_DEFAULT` is
  rejected (stricter than Cloud Posse, which passes it to AWS, where it has no effect).
- `string_schemas` attributes cannot be changed or removed once the pool exists (AWS); adding one
  is in place. Name custom attributes without `custom:`; only standard attributes can be
  `required` (validated).
- `lambda_config` takes Cloud Posse `aws-cognito`'s trigger keys as one typed object (its
  `kms_key_id` and custom sender triggers are not ported). Each function must be in the pool's
  region (validated). The component grants `cognito-idp.amazonaws.com` `lambda:InvokeFunction` on
  each, scoped to the pool's ARN; Cloud Posse leaves that grant to the caller, but the function's
  own component cannot scope it without reading the pool, which reads the function.
- A prod pool keeps `deletion_protection` (`check-prod-protection.py`).
