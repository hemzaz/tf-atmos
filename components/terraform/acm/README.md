# acm

One ACM certificate per `dns_domains` entry, DNS-validated through Route53 records in `zone_id`,
then waited on by `aws_acm_certificate_validation` (45 minute timeout).

## Wiring

- `acm/main` (`*.<d>` + `<d>`; prod adds `*.api.<d>`) reads `network/main .zone_ids.main`.
- `acm/services` (`*.services.<d>` + `api.services.<d>`) reads `network/services .zone_ids.services`.
- Used by: `apigateway` (`certificate_arns`), `monitoring` (`certificate_arns`,
  `certificate_domains`, expiry alarms).

## Notes

- One zone per instance: every certificate and SAN must sit inside it, and not inside a more
  specific public zone of the stack (`check-domains.py` enforces this).
- Validation records are keyed per record name: the domain without `*.`, across all
  certificates of the instance (`x` and `*.x` share one CNAME), as in Cloud Posse
  `acm-request-certificate`. Each certificate's validation precondition requires a record for
  every one of its validation names.
- `deploy-full-stack` applies acm in its own `certificates` layer, after `dns` and before
  `services`. Validation cannot finish until the top-level domain is delegated (see `dns`).
- `certificate_keys` / `certificate_crts` are placeholder strings: ACM cannot export private keys.
  Use `scripts/certificates/export-cert.sh`.
