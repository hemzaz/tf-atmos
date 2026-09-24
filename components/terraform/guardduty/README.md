# guardduty

Enables the GuardDuty detector for one account/region, turns the S3, EKS audit
log and EBS malware protection plans on or off, and creates ARCHIVE finding
filters that suppress noise from the active finding list.

## Deployed

`guardduty/main` in all three stacks (`fnx-dev-testenv-01`,
`fnx-staging-staging-01`, `fnx-prod-production`), each in
`components/security.yaml`, inheriting the abstract `guardduty/defaults` from
`stacks/catalog/guardduty/defaults.yaml`.

The catalog follows the Cloud Posse aws-guardduty defaults: S3 protection on,
EKS audit logs and EBS malware scanning off (they bill per event / per GB
scanned). Prod turns both on and adds a Recon:EC2/Portscan auto-archive filter.

| Inputs (required) | Inputs (behavior) | Outputs |
|---|---|---|
| region, tags (needs a non-empty `Environment`) | enable, enable_s3_protection, enable_kubernetes_protection, enable_malware_protection, finding_publishing_frequency, auto_archive_filter | `detector_id` (read by `security-monitoring/main`), `detector_arn`, `enabled_features`, `auto_archive_filter_arns` |

## Dependencies & gotchas

- No `dependencies.components` of its own. `security-monitoring/defaults`
  lists `guardduty/main` as a dependency and reads `.detector_id`.
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
- This component is the only owner of the detector. `security-monitoring`
  consumes `detector_id` and creates no detector, and
  `workflows/scripts/security/harden.sh` deploys this component instead of
  calling `aws guardduty create-detector`.

## Usage

```
atmos terraform plan guardduty/main -s fnx-prod-production
```
