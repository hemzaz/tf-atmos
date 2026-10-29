
data "awsutils_caller_identity" "current" {
  count = !var.bypass && local.dynamic_terraform_role_enabled ? 1 : 0
  # Avoid conflict with caller's provider which is using this module's output to assume a role.
  provider = awsutils.iam-roles
}

module "always" {
  source  = "cloudposse/label/null"
  version = "0.25.0"

  # account_map must always be enabled, even for components that are disabled
  enabled = true

  context = module.this.context
}

module "account_map" {
  source  = "cloudposse/stack-config/yaml//modules/remote-state"
  version = "2.0.1"

  bypass      = var.bypass
  component   = "account-map"
  privileged  = var.privileged
  tenant      = var.overridable_global_tenant_name
  environment = var.overridable_global_environment_name
  stage       = var.overridable_global_stage_name

  context = module.always.context
}

locals {
  profiles_enabled = var.bypass ? false : coalesce(var.profiles_enabled, local.account_map.profiles_enabled)

  dynamic_terraform_role_enabled = var.bypass ? false : try(local.account_map.terraform_dynamic_role_enabled, false)

  account_map       = module.account_map.outputs
  account_name      = var.bypass ? "" : lookup(module.always.descriptors, "account_name", module.always.stage)
  root_account_name = var.bypass ? "" : local.account_map.root_account_account_name

  current_user_role_arn = var.bypass ? "arn:aws:iam::000000000000:role/disabled" : coalesce(one(data.awsutils_caller_identity.current[*].eks_role_arn), one(data.awsutils_caller_identity.current[*].arn), "arn:${local.account_map.aws_partition}:iam::000000000000:role/disabled")

  current_identity_account = local.dynamic_terraform_role_enabled ? split(":", local.current_user_role_arn)[4] : ""

  terraform_access_map = var.bypass ? {} : try(local.account_map.terraform_access_map[local.current_user_role_arn], {})

  is_root_user   = var.bypass ? false : local.current_identity_account == local.account_map.full_account_map[local.root_account_name]
  is_target_user = var.bypass ? false : local.current_identity_account == local.account_map.full_account_map[local.account_name]

  account_org_role_arns = var.bypass ? {} : { for name, id in local.account_map.full_account_map : name =>
    name == local.root_account_name ? null : format(
      "arn:%s:iam::%s:role/OrganizationAccountAccessRole", local.account_map.aws_partition, id
    )
  }

  static_terraform_roles = var.bypass ? {} : local.account_map.terraform_roles

  dynamic_terraform_role_maps = local.dynamic_terraform_role_enabled ? {
    for account_name in local.account_map.all_accounts : account_name => {
      apply = format(local.account_map.iam_role_arn_templates[account_name], local.account_map.terraform_role_name_map["apply"])
      plan  = format(local.account_map.iam_role_arn_templates[account_name], local.account_map.terraform_role_name_map["plan"])
      # For user without explicit permissions:
      #   If the current user is a user in the `root` account, assume the `OrganizationAccountAccessRole` role in the target account.
      #   If the current user is a user in the target account, do not assume a role at all, let them do what their role allows.
      #   Otherwise, force them into the static Terraform role for the target account,
      #   to prevent users from accidentally running Terraform in the wrong account.
      none = local.is_root_user ? local.account_org_role_arns[account_name] : (
        # null means use current user's role
        local.is_target_user ? null : local.static_terraform_roles[account_name]
      )
    }
  } : {}

  dynamic_terraform_role_types = local.dynamic_terraform_role_enabled ? { for account_name in local.account_map.all_accounts :
    account_name => try(local.terraform_access_map[account_name], "none")
  } : {}

  dynamic_terraform_roles = local.dynamic_terraform_role_enabled ? { for account_name in local.account_map.all_accounts :
    account_name => local.dynamic_terraform_role_maps[account_name][local.dynamic_terraform_role_types[account_name]]
  } : {}

  final_terraform_role_arns = local.dynamic_terraform_role_enabled ? { for account_name in local.account_map.all_accounts :
    account_name => local.dynamic_terraform_roles[account_name]
  } : local.static_terraform_roles
}
