# dns

Route53 hosted zones, records, health checks, traffic policies and private-zone VPC
associations. A zone's `parent_zone` makes the component write its NS delegation record into
the parent zone of the same instance (Cloud Posse `dns-delegated`'s pattern).
`multi_account_dns_delegation` moves zones without `vpc_associations` to the `aws.dns_account`
provider.

## Wiring

Instances are named `network/main` and `network/services` (`metadata.component: dns`) in the
three AWS stacks; `network/main` also in `fnx-local-sandbox`. `network/vpc-peering` is a
different component (`network`).

- In the AWS stacks, `network/main` reads `vpc/main .vpc_id` (private `internal` zone) and
  `network/services .zone_name_servers.services` (NS record delegating `services.<d>`); in prod
  also `rds/main .instance_address` (`db.internal.<d>` CNAME).
- Used by: `acm` (`zone_ids`, validation zone), `apigateway` (`zone_ids`, alias records),
  `eks-addons` (`zone_ids`, external-dns and cert-manager).

Zones (`<d>` = `settings.environment.domain_name`): `network/main` holds `main` = `<d>` and
private `internal` = `internal.<d>`; `network/services` holds `services.<d>` and
`data.services.<d>` (delegated by `parent_zone`).

## Notes

- `network/services` deploys in its own `dns-zones` layer before the `dns` layer
  (`deploy-full-stack`), because `network/main` reads its name servers.
- `<d>` itself must be delegated from its parent domain manually, by the owner, before the first
  `deploy-certificates`; ACM validation hangs otherwise. See [docs/OPERATIONS.md](../../../docs/OPERATIONS.md#deploying-a-stack).
- `enable_query_logging` is rejected for private zones (use Resolver query logging).
- Records in a DNS-account zone can only reference health checks from the main account.
- `workflows/scripts/common/check-domains.py` (run by `validate-all`) requires every record name
  to sit in its zone and not inside a more specific public zone of the stack, and every nested
  public zone to be delegated from its parent.
