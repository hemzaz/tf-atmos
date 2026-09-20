# idp-platform

Monolithic "internal developer platform" component: nests the `eks`, `rds`
and `acm` root components as modules (each with its own `provider` block),
and directly creates ALB + Redis security groups, an ElastiCache Redis
replication group, S3 buckets (artifacts/backups/logs/techdocs/uploads), an
ALB, a Route53 zone + health check, and CloudWatch health alarms.

**Status: unsupported.** `main.tf` has a `terraform_data.unsupported`
precondition that fails planning unless `acknowledge_unsupported = true` —
nesting root components with their own provider blocks is a legacy pattern;
the shared logic needs to move to `modules/terraform` first.

## Deployed

Not currently deployed in any stack: zero instances in fnx-dev-testenv-01,
fnx-staging-staging-01, or fnx-prod-production. No stack imports this
component today.

| Inputs (required) | Inputs (behavior) | Outputs |
|---|---|---|
| region, environment, domain_name (plus acknowledge_unsupported=true to plan at all) | database_instance_class, redis_node_type, cluster_version, cluster_endpoint_public_access (now default false; needs cluster_endpoint_public_access_cidrs when true), enable_disaster_recovery/enable_cost_optimization/enable_security_scanning | 40+ outputs (eks/rds/redis/s3/alb/route53/acm/secrets) — no consumers since it's undeployed |

## Dependencies & gotchas

- No `dependencies.components` entries exist (no stack instance to declare them on).
- Several boolean flags (e.g. enable_disaster_recovery, enable_cost_optimization)
  may not wire to real resources — verify in main.tf before relying on them.
- Nested provider blocks are fragile under `for_each`/`depends_on`; resolve
  the unsupported precondition before applying.
- **`notification_endpoints.slack` / `.teams` must be a forwarder, not a
  webhook.** SNS only begins delivering to an HTTPS subscription once the
  endpoint answers a `SubscriptionConfirmation` POST by fetching the token URL
  inside it. A raw Slack or Teams incoming webhook never does, so the
  subscription would sit in `PendingConfirmation` and deliver nothing, silently.
  Point these at something that confirms and reshapes the payload — a Lambda
  function URL, an API Gateway, or AWS Chatbot.

  Setting either field therefore requires `acknowledge_https_forwarder = true`.
  That flag, not the hostname check below, is the real guard: no URL inspection
  can prove an endpoint confirms subscriptions, and the failure it prevents is
  silent and permanent.

  A second validation rejects the raw-webhook hosts worth naming —
  `hooks.slack.com`, `*.webhook.office.com`, `*.logic.azure.com` (the Power
  Automate URLs that replaced retired Office 365 connectors) and Discord — but
  treat it as a better error message, not a guarantee. Those hosts move:
  Office 365 connectors retired in May 2026 and the `logic.azure.com` URLs are
  themselves being relocated, so the list lags and fails **open** on whatever
  is current.

  `notification_endpoints.email` needs neither flag nor forwarder — each
  address gets a confirmation mail from AWS.
- `environment` only accepts `dev`, `staging` or `prod`, and the `domain_name`
  regex allows exactly one dot — so `example.com` validates but the subdomain
  `idp.example.com` does not. Both are stricter than the rest of the repo and
  are worth loosening if this component is ever adopted.

## Usage

A stack must add an instance first; then, with `acknowledge_unsupported = true`:
```
atmos terraform plan idp-platform -s fnx-dev-testenv-01
```
