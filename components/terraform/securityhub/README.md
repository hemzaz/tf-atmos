# securityhub

Enables Security Hub for one account and region with consolidated control findings and subscribes
the standards in `standards`, given as short `<name>/v/<version>` paths.

## Wiring

- Instance: `securityhub/main` in the three AWS stacks; prod adds `pci-dss/v/3.2.1`.
- Depends on `awsconfig/main` (ordering only): most controls evaluate AWS Config recordings.
- Used by: `security-monitoring` (`.account_arn`). `harden.sh` deploys this component.

## Notes

- This component is the only owner of the hub.
- `enable_default_standards = true` lets AWS subscribe FSBP v1.0.0 and CIS v1.2.0 itself; those are
  filtered out of `standards` so the apply does not subscribe them twice.
- CIS v1.2.0 uses the partition-wide `:::ruleset/` ARN; every other standard `:<region>::standards/`.
- `disabled_security_controls` disables controls per subscribed standard
  (`aws_securityhub_standards_control_association`). `fnx-ue2-prod` disables, per AWS's "Controls
  that you might want to disable": the IAM controls and KMS.1/KMS.2 (global resources; AWS Config
  records them in us-east-1 only) and CloudWatch.1-14 (metric filters on the trail's log group,
  which is in us-east-1). An ID not in that standard fails at apply.
  Cloud Posse's `aws-security-hub` has no such input; this is an extension.
