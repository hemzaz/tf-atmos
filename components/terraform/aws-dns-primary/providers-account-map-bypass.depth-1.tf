# providers.tf for components that support BOTH authentication patterns:
#   - WITH account-map  (`account_map_enabled = true`, the default): the AWS provider
#     assumes the per-stack Terraform role looked up via the `account-map` component's
#     `iam-roles` submodule (the standard cross-account "provider hop").
#   - WITHOUT account-map (`account_map_enabled = false`): `module.iam_roles` is bypassed
#     and the provider uses whatever credentials are already in the environment (e.g. when
#     Atmos Auth delivers target-account credentials directly). No role is assumed.
#
# This lets a single component be migrated from the account-map pattern to the
# account-map-less pattern by flipping `account_map_enabled` per stack — no providers.tf
# change required. Pair it with `account-verification.mixin.tf` to guard against running
# against the wrong account when account-map is bypassed. When `account_map_enabled = false`,
# also populate `account_map.full_account_map` (the default is empty) so the verification guard
# can actually validate the ambient credentials; otherwise the guard is a no-op and the component
# trusts whatever AWS credentials are present in the environment.
#
# Depth 1: use this variant for components at `components/terraform/<name>/`.
# The only difference between the depth variants is the `module.iam_roles` source path.

variable "account_map_enabled" {
  type        = bool
  description = "Enable the account-map component lookup. When false, bypass it and use the credentials already present in the environment (account-map-less)."
  default     = true
}

variable "account_map" {
  type = object({
    full_account_map              = map(string)
    audit_account_account_name    = optional(string, "")
    root_account_account_name     = optional(string, "")
    identity_account_account_name = optional(string, "")
    aws_partition                 = optional(string, "aws")
    iam_role_arn_templates        = optional(map(string), {})
  })
  description = "Map of account names (tenant-stage format) to account IDs. Used (e.g. by the account-verification mixin) to verify the correct target account when account_map_enabled is false. Optional attributes support component-specific functionality (e.g. audit_account_account_name for cloudtrail, root_account_account_name for aws-sso)."
  default = {
    full_account_map              = {}
    audit_account_account_name    = ""
    root_account_account_name     = ""
    identity_account_account_name = ""
    aws_partition                 = "aws"
    iam_role_arn_templates        = {}
  }
}

provider "aws" {
  region = var.region

  # Profile is deprecated in favor of terraform_role_arn. When profiles are not in use, terraform_profile_name is null.
  profile = var.account_map_enabled ? module.iam_roles.terraform_profile_name : null

  dynamic "assume_role" {
    # module.iam_roles.terraform_role_arn may be null, in which case do not assume a role.
    for_each = var.account_map_enabled ? compact([module.iam_roles.terraform_role_arn]) : []
    content {
      role_arn = assume_role.value
    }
  }
}

module "iam_roles" {
  source  = "../account-map/modules/iam-roles"
  bypass  = !var.account_map_enabled
  context = module.this.context
}
