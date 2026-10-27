# Changelog

All notable changes to this component will be documented in this file.

## [2.0.0] - 2026-01-06

### Breaking Changes

- **Complete refactor to single-resource pattern**: This component now manages exactly one `aws_organizations_policy` resource with optional attachment, replacing the previous approach bundled with the monolithic `account` component.
- **Requires OpenTofu >= 1.7.0**: For `for_each` support in import blocks.

### Added

- Single-resource pattern for managing individual Service Control Policies
- Flexible policy input: Use `policy_statements` (structured) or `policy_content` (raw JSON)
- Optional policy attachment via `target_id` and `attach_to_target` variables
- Import block support via `import_policy_id` variable
- Optional `imports.tf` file (can be excluded when vendoring if not needed)
- `skip_destroy` option for safe policy removal

### Migration

To migrate from the monolithic `account` component:

1. Get your policy IDs: `aws organizations list-policies --filter SERVICE_CONTROL_POLICY`
2. Configure each SCP component with `import_policy_id` set to the policy ID
3. Run `atmos terraform apply` to import
4. Remove the `import_policy_id` after successful import

### Related Components

| Component | Purpose |
|-----------|---------|
| `aws-organization` | Creates/imports the AWS Organization |
| `aws-organizational-unit` | Creates/imports a single OU |
| `aws-account` | Creates/imports a single AWS Account |
| `aws-account-settings` | Configures account settings |
| `aws-scp` | Creates/imports Service Control Policies (this component) |
