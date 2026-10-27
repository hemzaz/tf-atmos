# Changelog

All notable changes to this component will be documented in this file.

## [2.0.0] - 2026-01-06

### Breaking Changes

- **Complete refactor to single-resource pattern**: This component now manages exactly one `aws_organizations_organization` resource, replacing the previous monolithic approach.
- **Removed account management**: Use the new `aws-account` component instead.
- **Removed OU management**: Use the new `aws-organizational-unit` component instead.
- **Removed SCP management**: Use the new `aws-scp` component instead.
- **Requires OpenTofu >= 1.7.0**: For `for_each` support in import blocks.

### Added

- Single-resource pattern for managing the AWS Organization
- Import block support via `import_resource_id` variable
- Optional `imports.tf` file (can be excluded when vendoring if not needed)
- Outputs for organization details: `organization_id`, `organization_arn`, `organization_root_id`, `master_account_*`, `roots`

### Migration

To migrate from the monolithic `account` component:

1. Get your organization ID: `aws organizations describe-organization --query 'Organization.Id' --output text`
2. Configure the component with `import_resource_id` set to the organization ID
3. Run `atmos terraform apply` to import
4. Remove the `import_resource_id` after successful import

### Related Components

| Component | Purpose |
|-----------|---------|
| `aws-organization` | Creates/imports the AWS Organization (this component) |
| `aws-organizational-unit` | Creates/imports a single OU |
| `aws-account` | Creates/imports a single AWS Account |
| `aws-account-settings` | Configures account settings |
| `aws-scp` | Creates/imports Service Control Policies |
