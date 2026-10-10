# guardduty

The GuardDuty detector for one account and region, its S3, EKS audit log and EBS malware
protection plans, and ARCHIVE finding filters. Defaults follow Cloud Posse `aws-guardduty`: S3
protection on, EKS and malware scanning off (prod turns both on).

## Wiring

- Instance: `guardduty/main` in the three AWS stacks, `fnx-ue2-prod`, `fnx-ew1-prod` and
  `fnx-ec1-prod`; the prod
  stacks inherit `guardduty/prod` (`stacks/catalog/guardduty/prod.yaml`).
- Used by: `security-monitoring` (`.detector_id`). `workflows/scripts/security/harden.sh`
  deploys this component rather than calling the GuardDuty API.

## Notes

- This component is the only owner of the detector; `enable = false` destroys it and its filters.
- Protection plans are `aws_guardduty_detector_feature` resources (AWS provider 6.x).
- Each `auto_archive_filter` needs at least one `criteria` field (a severity-only rule would
  archive everything at that severity). Filter rank follows list order, so reordering renames
  and re-ranks filters.
