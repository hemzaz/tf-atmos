# acm

Creates one `aws_acm_certificate` per entry in `var.dns_domains`, DNS-validates each via
`aws_route53_record` in `var.zone_id`, then waits on `aws_acm_certificate_validation`
(45m timeout). Preconditions enforce a valid domain regex and `validation_method` in
(DNS, EMAIL); postconditions check the certificate reached ISSUED/PENDING_VALIDATION.

## Deployed as

Real instances `acm/main` and `acm/services` in all 3 stacks: `fnx-dev-testenv-01`,
`fnx-staging-staging-01`, `fnx-prod-production`. Both inherit an abstract `acm/defaults`
catalog entry (not a real instance itself).

| Instance | Certificate (`<d>` = `settings.environment.domain_name`) | `zone_id` |
|---|---|---|
| `acm/main` | `*.<d>` + `<d>` (prod also `*.api.<d>`) | `!terraform.state network/main .zone_ids.main` (zone `<d>`) |
| `acm/services` | `*.services.<d>` + `api.services.<d>` | `!terraform.state network/services .zone_ids.services` (zone `services.<d>`) |

`<d>` is `fnx.example.com` (prod), `staging.fnx.example.com` (staging) and
`dev.fnx.example.com` (dev), placeholders until the real domain is set.

## Inputs / Outputs

| Input | Notes |
|---|---|
| `dns_domains` | map of domain -> {domain_name, subject_alternative_names, validation_method} |
| `zone_id` | Route53 zone for DNS validation; required, validated as `Z...`. Every DNS-validated certificate's domain and SANs must be inside it (`workflows/scripts/common/check-domains.py`) |
| `tags` | must include an `Environment` key |

Output `certificate_arns` is consumed by `apigateway/main`, `apigateway/data`,
`monitoring/main`, `monitoring/data` via `!terraform.state acm/main|services .certificate_arns...`.

## Dependencies / gotchas

- `zone_id` reads the dns instance's `zone_ids` output, so each instance lists that dns
  instance (`network/main` / `network/services`) in `dependencies.components`, and
  `deploy-full-stack` applies acm in its own `certificates` layer, after `dns` and before
  the `services` and `monitoring` layers that read `certificate_arns`.
- One `zone_id` per instance: every certificate of an instance validates in the same zone.
  A name that belongs to a more specific public zone of the stack (for example
  `data.services.<d>`, the apex of `network/services`' `data` zone) cannot be a SAN of a
  certificate validated in its parent zone; `check-domains.py` rejects it.
- `aws_route53_record.validation` has one record per distinct validation name: keyed by the
  domain without `*.` across all DNS-validated certificates, which is one key per
  `resource_record_name` (`x` and `*.x` share a CNAME, as does the same name in two
  certificates). The record names themselves are unknown until the certificate exists, so they
  cannot be `for_each` keys; Cloud Posse's `acm-request-certificate` counts distinct names the
  same way. One resource per record, so destroying one no longer deletes a record another
  still uses.
- `aws_acm_certificate_validation`'s precondition requires a record for every distinct
  `resource_record_name` of that certificate's validation options. It used to count every
  record in the instance, so any instance with two or more certificates failed at apply.
- `certificate_keys` / `certificate_crts` outputs are placeholder strings only — ACM's
  API cannot export private keys or cert bodies; use `scripts/certificates/export-cert.sh`.
- `tags` without an `Environment` key fails validation before any plan.

## Tests

`tests/validation.tftest.hcl` plans one certificate, two certificates, a wildcard + apex
certificate (one shared record), a DNS + EMAIL mix, and a validation option without a record
(the precondition fails) against a mock provider (`override_during = plan`, per-certificate
`domain_validation_options` overrides), so the precondition is evaluated:
`terraform init -backend=false && terraform test`.

## Usage

```
atmos terraform plan acm/main -s fnx-dev-testenv-01
atmos terraform plan acm/services -s fnx-prod-production
```
