# Changelog

All notable changes to this component will be documented in this file.

## [2.0.0] - 2026-01-06

### Breaking Changes

- **Removed budgets management**: Use the separate `aws-budgets` component instead.
- **Removed service quotas management**: Use the separate `aws-service-quotas` component instead.
- **Removed IAM password policy**: Use AWS defaults or a separate component.
- **Removed `iam-roles` module dependency**: Simple provider configuration now.
- **Requires OpenTofu >= 1.7.0**: For `for_each` support in import blocks.

### Added

- **S3 account-level public access block**: Enabled by default for security.
- **Alternate contacts support**: Configure billing, operations, and security contacts.
- **SSM Session Manager preferences**: Configurable idle timeout.
- **EBS default KMS key support**: Use custom KMS key for EBS encryption.
- **Import block support**: Import existing IAM account alias via `import_account_alias` variable.
- **Optional `imports.tf` file**: Can be excluded when vendoring if not needed.

### Removed

| Removed Feature | Migration Path |
|-----------------|----------------|
| Budgets management | Use separate `aws-budgets` component |
| Service quotas management | Use separate `aws-service-quotas` component |
| IAM password policy | Use AWS defaults or separate component |
| `iam-roles` module dependency | Simple provider configuration |

### Migration

See [docs/migration.md](../docs/migration.md) for detailed migration instructions.
