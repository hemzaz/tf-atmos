# Change log for aws-sso component

**_NOTE_**: This file is manually generated and is a work-in-progress.

## v2.0.2

### Bug Fixes

- Added `v1-providers.tf` mixin with real `iam-roles` module and role-assuming provider for account-map users
- Added `v1-variables.tf` mixin with shared variable definitions required by v1 policy mixins
- Moved `var.tfstate_environment_name` from `policy-TerraformUpdateAccess.tf` into `v1-variables.tf`
- Moved `var.privileged` into the `v1-providers.tf` mixin (needed by `iam-roles` module)
- Restored dummy `module.iam_roles` in default `providers.tf` (satisfies mixin references)
- Changed `account_map_enabled` default to `false` (account-map users vendor the providers mixin)
- Refactored `remote-state.tf` to use component context instead of `module.iam_roles` outputs
- Updated `MIGRATION.md` to document the providers mixin requirement for v1 policy support
- Updated mixins `README.md` with dependency documentation

---

## v2.0.0 (BREAKING)

This is a major release that simplifies the component architecture by removing the separate root account provider configuration.

### Breaking Changes

- **Removed `aws.root` provider**: The component no longer configures a separate AWS provider for the root account. This reflects the updated recommendation to deploy AWS SSO directly to the root account rather than delegating to an identity account.
- **Removed `sso_account_assignments_root` module**: Root account assignments are no longer handled separately.
- **Removed policy files from `src/`**: The following policy files have been moved to `mixins/` for optional use:
  - `policy-TerraformUpdateAccess.tf`
  - `policy-Identity-role-TeamAccess.tf`
- **Removed variables**:
  - `privileged`
  - `aws_teams_accessible`
  - `overridable_team_permission_set_name_pattern`
  - `tfstate_backend_component_name`

### Migration

See [MIGRATION.md](./MIGRATION.md) for detailed migration instructions.

### New Features

- **Static account map support**: Set `account_map_enabled = false` to use static account mappings via the `account_map` variable, eliminating the dependency on the `account-map` component remote state lookup

### What's Changed

- Simplified `providers.tf` to use a basic AWS provider configuration
- Added dummy `module.iam_roles` to satisfy module dependencies during transition
- Moved optional policy files to `mixins/` directory for vendor-based inclusion
- Added `account_map_enabled` variable (default: `false`) with improved description
- Extended `account_map` variable with additional optional fields (`identity_account_account_name`, `aws_partition`, `iam_role_arn_templates`)

---

### PR 830

- Fix `providers.tf` to properly assign roles for `root` account when deploying to `identity` account.
- Restore the `sts:SetSourceIdentity` permission for Identity-role-TeamAccess permission sets added in PR 738 and
  inadvertently removed in PR 740.
- Update comments and documentation to reflect Cloud Posse's current recommendation that SSO **_not_** be delegated to
  the `identity` account.

### Version 1.240.1, PR 740

This PR restores compatibility with `account-map` prior to version 1.227.0 and fixes bugs that made versions 1.227.0 up
to this release unusable.

Access control configuration (`aws-teams`, `iam-primary-roles`, `aws-sso`, etc.) has undergone several transformations
over the evolution of Cloud Posse's reference architecture. This update resolves a number of compatibility issues with
some of them.

If the roles you are using to deploy this component are allowed to assume the `tfstate-backend` access roles (typically
`...-gbl-root-tfstate`, possibly `...-gbl-root-tfstate-ro` or `...-gbl-root-terraform`), then you can use the defaults.
This configuration was introduced in `terraform-aws-components` v1.227.0 and is the default for all new deployments.

If the roles you are using to deploy this component are not allowed to assume the `tfstate-backend` access roles, then
you will need to configure this component to include the following:

```yaml
components:
  terraform:
    aws-sso:
      backend:
        s3:
          role_arn: null
      vars:
        privileged: true
```

If you are deploying this component to the `identity` account, then this restriction will require you to deploy it via
the SuperAdmin user. If you are deploying this component to the `root` account, then any user or role in the `root`
account with the `AdministratorAccess` policy attached will be able to deploy this component.

## v1.227.0

This component was broken by changes made in v1.227.0. Either use a version before v1.227.0 or use the version released
by PR 740 or later.
