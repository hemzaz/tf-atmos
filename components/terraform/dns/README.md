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
  (`deploy-full-stack`), because `network/main` reads its name servers. The `external_zones`
  it signs come from `aws-dns-primary` (own `dns-apex` layer) and `aws-dns-delegated`
  (`dns-zones`, after the apex zone its plan looks up).
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
  in the DNS account. CloudWatch Logs allows 10 account-scoped resource policies per region and
  account; `check-domains.py` counts the house ones per account name (this policy, a logging
  `waf`'s; a DNS-account policy in the account its role ARN's id maps to) and fails an eleventh. Being
  us-east-1 only, it stays off on every zone of a GDPR-scoped (EU) stack (`check-data-residency.py` fails it); Resolver
  (in-VPC) query logging, which would stay in the stack region, is not modelled.
- `<first zone>` is the alphabetically first query-logged zone, so adding a zone that sorts earlier
  renames (replaces) the policy and the alias, briefly cutting Route53's write permission. Set
  `query_logging_name` once the zones are settled to pin the suffix. Setting it on an existing
  stack is itself a one-time replace of the policy and the alias, so pin it before the first
  apply. A caller-supplied `cloudwatch_log_group_arn` must be in the
  zone's account (a precondition on the query log).
- `query_log_retention_in_days` defaults to 7 (prod: 90). A zone's `query_logging_config` may
  set `retention_days`, a us-east-1 `kms_key_id` (no own key is then created for it) or a
  us-east-1 `cloudwatch_log_group_arn` (no log group is created; the policy still names it).
- `dnssec_enabled` (Cloud Posse `dns-delegated`'s input, default off) signs every public zone
  the instance creates: per account one us-east-1 `ECC_NIST_P256`/`SIGN_VERIFY` KMS key (Route 53
  only signs with us-east-1 keys; resource `region` argument; policy: account root plus
  `dnssec-route53.amazonaws.com` scoped to this account's hosted zones), per zone a key-signing
  key and `SIGNING`. Signing alone changes nothing for resolvers; the chain of trust starts when
  the owner publishes the zone's `ds_records` output at the registrar (apex) or parent zone. A
  `parent_zone` subzone gets its DS record (`delegation_ds_<key>`) beside its NS record in the
  parent; a zone delegated from another instance needs a `DS` record there reading this
  instance's `ds_records` (a `DS` record whose values are all null is dropped, so that read
  empties out cleanly). Records apply after `SIGNING`, so a DS never precedes its signatures.
- Turning DNSSEC off is two applies, or validating resolvers fail the zone: first
  `dnssec_ds_enabled: false` (removes `delegation_ds_*`, empties `ds_records` so readers drop
  theirs; remove the registrar DS by hand), wait out the DS TTL (registrar: often 1-2 days), then
  `dnssec_enabled: false`. `dnssec_ds_enabled` (null = `dnssec_enabled`) cannot be on without
  signing. The key is in us-east-1, so a GDPR-scoped (EU) stack keeps DNSSEC off.
- `external_zones` names public zones another component creates, such as a vendored Cloud Posse
  `aws-dns-delegated`/`aws-dns-primary` zone, which ships with no DNSSEC and no query logging.
  Each entry is found by `zone_id` or by name lookup, in this account or (`dns_account`) the
  DNS account (needs `dns_account_assume_role_arn`), never created, and must be public. A record's
  `zone_name` may name one. Per entry, `dnssec_enabled` signs it with this instance's key (needs the
  instance's `dnssec_enabled`; DS in `ds_records`, and `parent_zone`, never a private zone, gets it), and `enable_query_logging`
  logs it to a log group and key this instance creates. A zone takes one query logging config, so
  only one component may log it. Keys must differ from `zones` keys.
- Records in a DNS-account zone can only reference health checks from the main account.
- `workflows/scripts/common/check-domains.py` (run by `validate-all`) requires every record name
  to sit in its zone and not inside a more specific public zone of the stack, and every nested
  public zone to be delegated from its parent.
