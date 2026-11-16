# guardduty

The GuardDuty detector for one account and region, its S3, EKS audit log and EBS malware
protection plans, and ARCHIVE finding filters. Defaults follow Cloud Posse `aws-guardduty`: S3
protection on, EKS and malware scanning off (prod turns both on).

## Wiring

- Instance: none (E5c8): the organization's vendored `aws-guardduty` (delegated administrator in
  each `<tenant>-<env>-security` stack) replaced it; this component is deleted in E5c9.

## Notes

- This component is the only owner of the detector; `enable = false` destroys it and its filters.
- Protection plans are `aws_guardduty_detector_feature` resources (AWS provider 6.x).
- Each `auto_archive_filter` needs at least one `criteria` field (a severity-only rule would
  archive everything at that severity). Filter rank follows list order, so reordering renames
  and re-ranks filters.
