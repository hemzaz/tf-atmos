# inspector2

Enables Amazon Inspector for one account and region, scanning the resource types the
`auto_enable_*` flags select (EC2, ECR, Lambda and, opt-in, Lambda code). Modelled on Cloud Posse
`aws-inspector2`, single-account path only (see `main.tf`). Off by default: Inspector bills per
resource scanned.

## Wiring

- Instance: `inspector2/main` in the three AWS stacks, `fnx-ue2-prod`, `fnx-ew1-prod` and
  `fnx-ec1-prod`,
  `enabled: false` from `stacks/catalog/inspector2/defaults.yaml`. A stack opts in by setting
  `enabled: true` on it.
- Deploys in the `security` layer of `workflows/deploy-full-stack.yaml`.
- Used by: `security-monitoring` (`.account_id` as `inspector2_account_id`). The output is null
  while the component is disabled, which keeps security-monitoring's Inspector finding route off;
  enabling Inspector turns the route on at the next security-monitoring plan.

## Notes

- This component is the only owner of Inspector for the account; `enabled: false` (or removing a
  flag) disables scanning of those resource types.
- Organization mode (delegated administrator, organization auto-enable, member association) is
  not implemented: this repo has no AWS Organizations management or delegated-administrator
  stack. Each workload account enables itself instead.
- `auto_enable_lambda_code` needs `auto_enable_lambda`, and `enabled: true` needs at least one of
  EC2, ECR or Lambda (both validated).
