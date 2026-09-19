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

## Usage

A stack must add an instance first; then, with `acknowledge_unsupported = true`:
```
atmos terraform plan idp-platform -s fnx-dev-testenv-01
```
