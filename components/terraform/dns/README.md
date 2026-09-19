# dns

Creates Route53 hosted zones (`aws_route53_zone`), records, health checks, traffic
policies, and private-zone VPC associations. When `multi_account_dns_delegation` is
true, zones with no `vpc_associations` are created in a second account via the
`aws.dns_account` provider alias; reusable delegation sets can target either account.

## Deployed as

Real instances `network/main` and `network/services` (`metadata.component: dns`) in all
3 stacks: `fnx-dev-testenv-01`, `fnx-staging-staging-01`, `fnx-prod-production`. Both
inherit an abstract `dns` catalog entry. Not to be confused with `network/vpc-peering`,
a separate, `enabled: false` stub instance in the prod stack for a future (not yet
written) `network` component — unrelated to this `dns` folder.

## Inputs / Outputs

| Input | Notes |
|---|---|
| `zones` | map of zone -> {name, vpc_associations, enable_query_logging}; `vpc_associations` makes it private |
| `records` | keyed record map; `zone_name` must match a key in `zones` |
| `multi_account_dns_delegation` | routes zones with no `vpc_associations` to `aws.dns_account` |

Output `zone_ids` is consumed by `apigateway/main`/`apigateway/data` (`.zone_ids.main` / `network/services .zone_ids.data`).

## Dependencies / gotchas

- `network/main` declares `dependencies.components: vpc/main` (its `internal` zone's
  `vpc_associations` reads `!terraform.state vpc/main .vpc_id`). `network/services` has
  no such dependency.
- `enable_query_logging` is rejected by validation for zones that also set
  `vpc_associations` (private zones need Resolver query logging instead).
- Records in a DNS-account zone can only reference health checks from the main account.

## Usage

```
atmos terraform plan network/main -s fnx-dev-testenv-01
atmos terraform plan network/services -s fnx-prod-production
```
