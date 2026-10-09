# dns

Route53 hosted zones, records, health checks, traffic policies and private-zone VPC
associations. A zone's `parent_zone` makes the component write its NS delegation record into
the parent zone of the same instance (Cloud Posse `dns-delegated`'s pattern).
`multi_account_dns_delegation` moves zones without `vpc_associations` to the `aws.dns_account`
provider.

## Wiring

Instances are named `network/main` and `network/services` (`metadata.component: dns`) in the
three AWS stacks; `network/main` also in `fnx-ue1-local-sandbox` and in `fnx-ew1-prod` (the EU
apex: `main` and `internal`, no `network/services`). `network/vpc-peering` is a
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
- Delegation NS records (from `parent_zone`, and the stacks' `services_delegation`) use a 30 s
  TTL, Cloud Posse `dns-delegated`'s value, so a re-created subzone's name servers propagate
  quickly; `delegation_ttl` sets it for `parent_zone` records. The child zone's own apex NS
  record keeps Route 53's 172800.
- `enable_query_logging` is rejected for private zones (use Resolver query logging).
- Query logging (`query-logging.tf`) lives in **us-east-1** whatever the stack region: Route53
  only publishes there. Per zone a log group `/aws/route53/<zone>/queries`; per instance and
  account one CloudWatch Logs resource policy `route53-query-logging-<first zone>` (route53,
  scoped by `aws:SourceAccount`/`aws:SourceArn`; the `aws_route53_query_log` waits for it) and
  one KMS key `alias/route53-query-logs-<first zone>` (rotation on; account root plus
  `logs.us-east-1` scoped to `/aws/route53/*`), so the component works in any stack region. All
  three use the resource `region` argument, not a provider alias; DNS-account zones get theirs
  in the DNS account. CloudWatch Logs allows 10 resource policies per region and account. Being
  us-east-1 only, it stays off on every zone of a GDPR-scoped (EU) stack (`check-data-residency.py` fails it); Resolver
  (in-VPC) query logging, which would stay in the stack region, is not modelled.
- `<first zone>` is the alphabetically first query-logged zone, so adding a zone that sorts earlier
  renames (replaces) the policy and the alias, briefly cutting Route53's write permission. Set
  `query_logging_name` once the zones are settled to pin the suffix. Setting it on an existing
  stack is itself a one-time replace of the policy and the alias, so pin it before the first
  apply if you want a custom name. A caller-supplied `cloudwatch_log_group_arn` must be in the
  zone's account (a precondition on the query log).
- `query_log_retention_in_days` defaults to 7 (prod: 90). A zone's `query_logging_config` may
  set `retention_days`, a us-east-1 `kms_key_id` (no own key is then created for it) or a
  us-east-1 `cloudwatch_log_group_arn` (no log group is created; the policy still names it).
- Records in a DNS-account zone can only reference health checks from the main account.
- `workflows/scripts/common/check-domains.py` (run by `validate-all`) requires every record name
  to sit in its zone and not inside a more specific public zone of the stack, and every nested
  public zone to be delegated from its parent.
