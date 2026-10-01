# idp-platform

Monolithic "internal developer platform": nests the `../eks`, `../rds` and `../acm` root
components as modules (each with its own provider block) and directly creates ALB and Redis
security groups, an ElastiCache replication group, S3 buckets, an ALB, a Route53 zone with a health
check, and CloudWatch alarms.

## Status

Unsupported. No stack deploys it, and a `terraform_data.unsupported` precondition fails every plan
unless `acknowledge_unsupported = true`. Nesting root components with provider blocks is a legacy
pattern; the shared logic has to move to `modules/terraform` before this is adopted.

## Notes

- Because it nests `../eks`, `../rds` and `../acm`, changing their variables can break this
  component. `validate-all` catches it; per-component checks do not.
- `notification_endpoints.slack` / `.teams` must be an HTTPS forwarder that confirms SNS
  subscriptions (Lambda function URL, API Gateway, AWS Chatbot), never a raw webhook, which would
  stay `PendingConfirmation` forever. Setting either requires `acknowledge_https_forwarder = true`;
  the raw-webhook host check is only a better error message.
- The Redis AUTH token and the JWT secret are ephemeral `random_password`s sent only through
  write-only attributes (`*_wo`), as in `elasticache`. Nothing reads a secret back at plan: the CI
  plan role (ReadOnlyAccess) has no `secretsmanager:GetSecretValue`. Bump `secrets_version` to
  rotate both.
- `../rds` forces TLS, so the config secret's `database_url` (and the `database_connection_string`
  output) carry `sslmode=verify-full&sslrootcert=<database_ca_bundle_path>`: the app images must
  ship the RDS CA bundle at that path.
- `environment` accepts only `dev`, `staging` or `prod`, and `domain_name` allows exactly one dot
  (`example.com`, not `idp.example.com`).
