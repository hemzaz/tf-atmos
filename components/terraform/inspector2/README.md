# inspector2

Enables Amazon Inspector for one account and region, scanning the resource types the
`auto_enable_*` flags select (EC2, ECR, Lambda and, opt-in, Lambda code). Modelled on Cloud Posse
`aws-inspector2`, single-account path only (see `main.tf`). Off by default: Inspector bills per
resource scanned.

## Wiring

- Instance: none (E5c8): the organization's vendored `aws-inspector2` (delegated administrator in
  each `<tenant>-<env>-security` stack, org-settings committed `metadata.enabled: false`, owner
  OQ-IN) replaced it; this component is deleted in E5c9.
- Used by: nothing (security-monitoring routes Inspector findings by a flag).

## Notes

- This component is the only owner of Inspector for the account; `enabled: false` (or removing a
  flag) disables scanning of those resource types.
- Organization mode (delegated administrator, organization auto-enable, member association) is
  not implemented: this repo has no AWS Organizations management or delegated-administrator
  stack. Each workload account enables itself instead.
- `auto_enable_lambda_code` needs `auto_enable_lambda`, and `enabled: true` needs at least one of
  EC2, ECR or Lambda (both validated).
