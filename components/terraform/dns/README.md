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
| `zones` | map of zone -> {name, vpc_associations, enable_query_logging, parent_zone}; `vpc_associations` makes it private |
| `zones.<key>.parent_zone` | key of another public zone in `zones` that this public zone's name is below: the component writes this zone's NS record (record id `delegation_<key>`, its `name_servers`) into it, delegating the subzone (Cloud Posse `dns-delegated`'s pattern, within one instance) |
| `records` | keyed record map; `zone_name` must match a key in `zones` |
| `multi_account_dns_delegation` | routes zones with no `vpc_associations` to `aws.dns_account` |

Output `zone_ids` is consumed by `apigateway/main`/`apigateway/data` (`network/main .zone_ids.main` /
`network/services .zone_ids.data`), `acm/main`/`acm/services` (`network/main .zone_ids.main` /
`network/services .zone_ids.services`, for DNS validation) and `eks-addons`.

Every zone and record name derives from `settings.environment.domain_name` (`<d>`):
`network/main` has `main` = `<d>` (public) and `internal` = `internal.<d>` (private);
`network/services` has `services` = `services.<d>` and `data` = `data.services.<d>` (both
public). `<d>` is `fnx.example.com` (prod), `staging.fnx.example.com` (staging) and
`dev.fnx.example.com` (dev), placeholders until the real domain is set.

Delegation is wired here, so ACM can validate in every zone:

- `data.services.<d>` from `services.<d>`: `network/services`' `zones.data.parent_zone: services`.
- `services.<d>` from `<d>`: `network/main`'s `services_delegation` NS record in its `main`
  zone, whose records are `!terraform.state network/services .zone_name_servers.services`.
  So `network/services` deploys in its own `dns-zones` layer, before the `dns` layer
  (`deploy-full-stack`).
- `<d>` itself from its parent domain: manual, by the owner, before the first
  `deploy-certificates` (see `docs/DEPLOYMENT.md`).

## Dependencies / gotchas

- `network/main` declares `dependencies.components: vpc/main` (its `internal` zone's
  `vpc_associations` reads `!terraform.state vpc/main .vpc_id`) and `network/services`
  (the NS record). `network/services` has no such dependency.
- `enable_query_logging` is rejected by validation for zones that also set
  `vpc_associations` (private zones need Resolver query logging instead).
- Records in a DNS-account zone can only reference health checks from the main account.
- Each record's `name` must be its zone's name or below it, and not inside a more specific
  public zone of the same stack; `workflows/scripts/common/check-domains.py` (run by
  `validate-all`) enforces it, together with the acm and apigateway names written into these
  zones, and that every public zone below another public zone of the stack is delegated
  from it (by `parent_zone` or an NS record reading the child's `zone_name_servers`).

## Tests

`tests/delegation.tftest.hcl` (mock provider) covers `parent_zone`: the NS record's name,
zone and name servers, no record without it, and the validation rejecting a missing parent, a
parent the zone is not below, and private zones: `terraform init -backend=false && terraform test`.

## Usage

```
atmos terraform plan network/main -s fnx-dev-testenv-01
atmos terraform plan network/services -s fnx-prod-production
```
