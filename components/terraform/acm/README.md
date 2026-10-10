# acm

One ACM certificate per `dns_domains` entry, DNS-validated through Route53 records in `zone_id`,
then waited on by `aws_acm_certificate_validation` (45 minute timeout).

## Wiring

- `acm/main` (`*.<d>` + `<d>`; prod adds `*.api.<d>`) reads `network/main .zone_ids.main`;
  `fnx-ew1-prod`'s is the EU apex's, in its own zone.
- `acm/services` (`*.services.<d>` + `api.services.<d>`) reads `network/services .zone_ids.services`.
- The DR stacks' `acm/main` (`api.<d>`: `fnx-ue2-prod`, `fnx-ec1-prod`) set
  `process_domain_validation_options: false` and no `zone_id`: each waits on the record its
  primary's `acm/main` (`fnx-ue1-prod`, `fnx-ew1-prod`) writes, and depends on it.
- Used by: `apigateway` (`certificate_arns`), `monitoring` (`certificate_arns`,
  `certificate_domains`, expiry alarms).

## Notes

- One zone per instance: every certificate and SAN must sit inside it, and not inside a more
  specific public zone of the stack (`check-domains.py` enforces this).
- Validation records are keyed per record name: the domain without `*.`, across all
  certificates of the instance (`x` and `*.x` share one CNAME), as in Cloud Posse
  `acm-request-certificate`. Each certificate's validation precondition requires a record for
  every one of its validation names.
- Within one account ACM gives a name the same validation CNAME in every certificate, and `x`
  the same as `*.x`. A certificate whose names another state's certificate already carries (a DR
  region's copy) must set `process_domain_validation_options: false` (Cloud Posse
  `acm-request-certificate`'s flag): otherwise both states own one record (`allow_overwrite`
  lets both create it), and destroying either deletes it and breaks the other's renewal. Such a
  certificate writes no record, needs no `zone_id` (required only while a DNS certificate
  processes its options), and, unlike upstream, is still waited on. The owning instance must
  deploy first and outlive it, keeping the name. `check-domains.py` fails such a certificate
  unless each of its names is carried by a processed DNS certificate of an acm instance in its
  `dependencies.components`, in the same account.
- `deploy-full-stack` applies acm in its own `certificates` layer, after `dns` and before
  `services`. Validation cannot finish until the top-level domain is delegated (see `dns`).
- `certificate_keys` / `certificate_crts` are placeholder strings: ACM cannot export private keys.
  Use `scripts/certificates/export-cert.sh`.
