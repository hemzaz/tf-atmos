# guardduty

Enables the GuardDuty detector for one account/region, turns the S3, EKS audit
log and EBS malware protection plans on or off, and creates ARCHIVE finding
filters that suppress noise from the active finding list.

## Deployed

`guardduty/main` only, in fnx-prod-production
(`stacks/orgs/fnx/prod/eu-west-2/production/components/security.yaml`).
Grepping dev and staging stacks for `guardduty` finds no reference — those
environments don't deploy it today, so every input except `region`/`tags`
has a default.

| Inputs (required) | Inputs (behavior) | Outputs |
|---|---|---|
| region, tags (needs a non-empty `Environment`) | enable, enable_s3_protection, enable_kubernetes_protection, enable_malware_protection, finding_publishing_frequency, auto_archive_filter | `detector_id`, `detector_arn`, `enabled_features`, `auto_archive_filter_arns` — nothing reads these yet |

## Dependencies & gotchas

- No `dependencies.components` entries in the map.
- On AWS provider 6.x protection plans are `aws_guardduty_detector_feature`
  resources, not inline `datasources` blocks on the detector.
- `enable = false` destroys the detector (and with it every finding filter),
  rather than leaving a disabled one in place.
- `auto_archive_filter[*].criteria` maps a GuardDuty finding field to the
  values it must equal, e.g. `type: ["Recon:EC2/Portscan"]`. At least one
  field is required — a severity-only rule would archive every finding at
  that severity.
- Filter `rank` is assigned from list order, so reordering
  `auto_archive_filter` renames and re-ranks the filters.
- This overlaps `security-monitoring`, which also manages a detector. Only
  one of the two may be enabled per account/region.

## Usage

```
atmos terraform plan guardduty/main -s fnx-prod-production
```
