# Changelog

All notable changes to this component will be documented in this file.

## [2.0.0] - 2026-01-06

### Breaking Changes

- **Complete refactor to single-resource pattern**: This component now manages exactly one AWS account per instance, replacing the previous monolithic approach that managed the entire organization hierarchy.
- **Removed organization management**: Use the new `aws-organization` component instead.
- **Removed OU management**: Use the new `aws-organizational-unit` component instead.
- **Removed SCP management**: Use the new `aws-scp` component instead.
- **Removed contacts management**: Use the `aws-account-settings` component instead.
- **New variables**: `account_email`, `parent_id`, `import_account_id`, `close_on_deletion`, `role_name`
- **Removed variables**: All organization hierarchy variables (`organization_config`, `aws_service_access_principals`, `enabled_policy_types`, etc.)
- **Requires OpenTofu >= 1.7.0**: For `for_each` support in import blocks.

### Added

- Single-resource pattern for managing individual AWS accounts
- Import block support via `import_account_id` variable
- Optional `imports.tf` file (can be excluded when vendoring if not needed)

### Migration

See [docs/migration.md](../docs/migration.md) for detailed migration instructions from the monolithic `account` component.

### Related Components

| Component | Purpose |
|-----------|---------|
| `aws-organization` | Creates/imports the AWS Organization |
| `aws-organizational-unit` | Creates/imports a single OU |
| `aws-account` | Creates/imports a single AWS Account (this component) |
| `aws-account-settings` | Configures account settings |
| `aws-scp` | Creates/imports Service Control Policies |
