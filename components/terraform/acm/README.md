# acm

Creates one `aws_acm_certificate` per entry in `var.dns_domains`, DNS-validates each via
`aws_route53_record` in `var.zone_id`, then waits on `aws_acm_certificate_validation`
(45m timeout). Preconditions enforce a valid domain regex and `validation_method` in
(DNS, EMAIL); postconditions check the certificate reached ISSUED/PENDING_VALIDATION.

## Deployed as

Real instances `acm/main` and `acm/services` in all 3 stacks: `fnx-dev-testenv-01`,
`fnx-staging-staging-01`, `fnx-prod-production`. Both inherit an abstract `acm/defaults`
catalog entry (not a real instance itself).

## Inputs / Outputs

| Input | Notes |
|---|---|
| `dns_domains` | map of domain -> {domain_name, subject_alternative_names, validation_method} |
| `zone_id` | Route53 zone for DNS validation; required, validated as `Z...` |
| `tags` | must include an `Environment` key |

Output `certificate_arns` is consumed by `apigateway/main`, `apigateway/data`,
`monitoring/main`, `monitoring/data` via `!terraform.state acm/main|services .certificate_arns...`.

## Dependencies / gotchas

- No `dependencies.components` entries; `zone_id` comes from
  `settings.environment.hosted_zone_id`, not another component's state.
- `certificate_keys` / `certificate_crts` outputs are placeholder strings only — ACM's
  API cannot export private keys or cert bodies; use `scripts/certificates/export-cert.sh`.
- `tags` without an `Environment` key fails validation before any plan.

## Usage

```
atmos terraform plan acm/main -s fnx-dev-testenv-01
atmos terraform plan acm/services -s fnx-prod-production
```
