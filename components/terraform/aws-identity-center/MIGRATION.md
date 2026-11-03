# Migration Guide for v2.0.0

This guide covers migrating from v1.x to v2.0.0 of the `aws-identity-center` component.

## Overview

Version 2.0.0 introduces a significant architectural change: **the removal of the separate `aws.root` provider configuration**. This change reflects the updated best practice of deploying AWS SSO directly to the root account, rather than delegating to a separate identity account.

In most modern deployments, there is no longer a separate identity account—everything is deployed to the same AWS account (typically root). This simplifies the architecture and removes the complexity of cross-account provider configurations.

## What's Changing

### Removed Provider Configuration

The `aws.root` provider alias has been removed from `providers.tf`. Previously, this provider was used to manage resources in the root account when the component was deployed to a different account (e.g., identity).

### Static Account Map Support

This version adds support for bypassing the `account-map` remote state lookup by using static account mappings. This is controlled by the `account_map_enabled` variable:

- **`account_map_enabled = false`** (default): Uses the static `account_map` variable instead, eliminating the dependency on the `account-map` component
- **`account_map_enabled = true`**: Uses the `account-map` component to look up account IDs dynamically via remote state. To enable this, vendor the `v1-providers.tf` mixin which sets the default to `true` and provides the real `iam-roles` module.

When using static account mappings, configure the `account_map` variable directly:

```yaml
components:
  terraform:
    aws-sso:
      vars:
        account_map_enabled: false
        account_map:
          full_account_map:
            core-root: "123456789012"
            core-audit: "234567890123"
            plat-dev: "345678901234"
            plat-staging: "456789012345"
            plat-prod: "567890123456"
          root_account_account_name: "core-root"
          identity_account_account_name: ""
          audit_account_account_name: "core-audit"
```

This is useful when:
- Using Atmos Auth profiles with static account mappings
- Simplifying dependencies by removing the `account-map` component requirement
- Deploying in environments where remote state lookups are not desired

### Removed Module

The `sso_account_assignments_root` module has been removed. This module previously handled account assignments that required the root provider.

### Moved to Mixins

The following policy files have been moved from `src/` to `mixins/` for optional vendor-based inclusion:

- `policy-TerraformUpdateAccess.tf` - Permission set for Terraform state access
- `policy-Identity-role-TeamAccess.tf` - Permission sets for team role assumption
- `v1-variables.tf` - Shared variable definitions required by both policy mixins above

### Removed Variables

The following variables have been removed:

| Variable | Purpose |
|----------|---------|
| `privileged` | Controlled role assumption behavior |
| `aws_teams_accessible` | List of teams for Identity-role-TeamAccess |
| `overridable_team_permission_set_name_pattern` | Pattern for team permission set names |
| `tfstate_backend_component_name` | Component name for tfstate backend lookup |

## Migration Steps

### Step 1: Check for Orphaned Resources

Before upgrading, run `terraform plan` with your current version to see if you have any resources managed by the `sso_account_assignments_root` module or the removed policy files.

### Step 2: Vendor the Root Provider Mixin (if needed)

If you have existing resources that were created with the `aws.root` provider, Terraform will fail with an error like:

```
Error: Provider configuration not present

To work with module.sso_account_assignments_root.aws_ssoadmin_account_assignment.this[...] (orphan)
its original provider configuration at provider["registry.terraform.io/hashicorp/aws"].root is required,
but it has been removed.
```

To resolve this, temporarily vendor the `provider-root.tf` mixin to allow Terraform to destroy these orphaned resources.

Add the following to your `component.yaml`:

```yaml
mixins:
  - uri: https://raw.githubusercontent.com/cloudposse-terraform-components/aws-identity-center/{{ .Version }}/mixins/provider-root.tf
    version: v1.540.0
    filename: provider-root.tf
```

Or add to your `vendor.yaml`:

```yaml
mixins:
  - source: "https://raw.githubusercontent.com/cloudposse-terraform-components/aws-identity-center/{{ .Version }}/mixins/provider-root.tf"
    version: "v1.540.0"
    filename: "provider-root.tf"
```

Then run:

```bash
atmos vendor pull -c aws-sso
```

### Step 3: Apply to Destroy Orphaned Resources

With the root provider mixin in place, run:

```bash
atmos terraform apply aws-sso -s <your-stack>
```

This will destroy the orphaned resources that were managed by the removed modules.

### Step 4: Remove the Root Provider Mixin

After the orphaned resources are destroyed, remove the `provider-root.tf` mixin from your vendor configuration and re-vendor:

```bash
atmos vendor pull -c aws-sso
```

### Step 5: Update Stack Configuration

If you are **not** using the v1 policy mixins (Step 6), remove references to the removed variables from your stack configuration:

```yaml
# Remove these from your vars if not using v1 mixins:
components:
  terraform:
    aws-sso:
      vars:
        # privileged: true  # REMOVE
        # aws_teams_accessible: []  # REMOVE
        # overridable_team_permission_set_name_pattern: "..."  # REMOVE
        # tfstate_backend_component_name: "..."  # REMOVE
```

If you **are** keeping the v1 mixins, leave these variables in place — they are defined by `v1-variables.tf` and still consumed by the policy mixins.

### Step 6: Vendor v1 Policy Mixins (if needed)

If you were using the `TerraformUpdateAccess` or `Identity-role-TeamAccess` permission sets and want to continue using them, you must vendor the following files:

1. **`v1-providers.tf`** (required) - Replaces the default providers.tf with account-map support and the real `iam-roles` module
2. **`v1-variables.tf`** (required) - Shared variable definitions removed in v2.0.0
3. The policy file(s) you need

```yaml
mixins:
  - uri: https://raw.githubusercontent.com/cloudposse-terraform-components/aws-identity-center/{{ .Version }}/mixins/v1-providers.tf
    version: v2.0.2
    filename: providers.tf
  - uri: https://raw.githubusercontent.com/cloudposse-terraform-components/aws-identity-center/{{ .Version }}/mixins/v1-variables.tf
    version: v2.0.2
    filename: v1-variables.tf
  - uri: https://raw.githubusercontent.com/cloudposse-terraform-components/aws-identity-center/{{ .Version }}/mixins/policy-TerraformUpdateAccess.tf
    version: v2.0.2
    filename: policy-TerraformUpdateAccess.tf
  - uri: https://raw.githubusercontent.com/cloudposse-terraform-components/aws-identity-center/{{ .Version }}/mixins/policy-Identity-role-TeamAccess.tf
    version: v2.0.2
    filename: policy-Identity-role-TeamAccess.tf
```

**`v1-providers.tf` is required.** The v1 policy mixins reference `module.iam_roles.global_stage_name` and `../account-map/modules/roles-to-principals`, which require the real `iam-roles` module. The default `providers.tf` uses a dummy module that does not provide these outputs. The `v1-providers.tf` mixin also defines `var.privileged`, which is needed by both the provider and the policy files.

**`v1-variables.tf` is required.** It defines `var.tfstate_backend_component_name`, `var.aws_teams_accessible`, and `var.overridable_team_permission_set_name_pattern` — variables that were removed from the main component in v2.0.0 but are still needed by the policy mixins.

You may vendor either or both policy files depending on which permission sets you need, but `v1-providers.tf` and `v1-variables.tf` must always be included alongside them.

Then add the permission sets to your `additional-permission-sets_override.tf`:

```hcl
locals {
  overridable_additional_permission_sets = concat(
    local.terraform_update_access_permission_set,
    local.identity_access_permission_sets,
    # ... other permission sets
  )
}
```

When using the `TerraformUpdateAccess` mixin, configure the terraform state variables in your stack:

```yaml
components:
  terraform:
    aws-sso:
      vars:
        tfstate_environment_name: "usw1"
        tf_access_bucket_arn: !terraform.state tfstate-backend core-usw1-root tfstate_backend_s3_bucket_arn
        tf_access_role_arn: !terraform.state tfstate-backend core-usw1-root tfstate_backend_access_role_arns["acme-core-gbl-root-tfstate"]
```

## Troubleshooting

### "Provider configuration not present" Error

This error occurs when Terraform state contains resources created with the `aws.root` provider, but that provider is no longer configured. Follow Step 2 above to temporarily add the provider mixin.

### Missing Permission Sets After Upgrade

If permission sets disappear after upgrading, you may have been using the policy files that were moved to mixins. Follow Step 6 to vendor them back in.

### Variable Validation Errors

If you see errors about unknown variables, remove the deprecated variables listed in Step 5 from your stack configuration.

## Questions?

If you encounter issues during migration, please open an issue at:
https://github.com/cloudposse-terraform-components/aws-identity-center/issues
