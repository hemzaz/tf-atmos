# securityhub

Enables Security Hub for one account and region with consolidated control findings and subscribes
the standards in `standards`, given as short `<name>/v/<version>` paths.

## Wiring

- Instance: none (E5c8): the organization's vendored `aws-security-hub` (delegated administrator in
  each `<tenant>-<env>-security` stack) replaced it; this component is deleted in E5c9.
- No finding aggregator: each region's findings stay in that region (the EU stacks' in the EU).
- Depends on `aws-config` (ordering only): most controls evaluate AWS Config recordings.
- Used by: nothing (security-monitoring routes the member hub's findings by a flag).

## Notes

- This component is the only owner of the hub.
- `enable_default_standards = true` lets AWS subscribe FSBP v1.0.0 and CIS v1.2.0 itself; those are
  filtered out of `standards` so the apply does not subscribe them twice.
- CIS v1.2.0 uses the partition-wide `:::ruleset/` ARN; every other standard `:<region>::standards/`.
- `disabled_security_controls` disables controls per subscribed standard
  (`aws_securityhub_standards_control_association`). `fnx-ue2-prod` and `fnx-ec1-prod` disable,
  per AWS's "Controls that you might want to disable": the IAM controls and KMS.1/KMS.2 (global
  resources; AWS Config records them only in the account's primary region, us-east-1 for prod,
  eu-west-1 for prod-eu) and CloudWatch.1-14 (metric filters on the trail's log group, which is in
  the account's primary region, us-east-1 for prod, eu-west-1 for prod-eu). An ID not in that
  standard fails at apply.
  Cloud Posse's `aws-security-hub` has no such input; this is an extension.
