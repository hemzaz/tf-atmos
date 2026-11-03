locals {
  enabled = module.this.enabled

  # module.account_map.outputs provides values from either remote state (when enabled)
  # or from the static var.account_map defaults (when bypassed)
  account_map = module.account_map.outputs.full_account_map

  account_assignments_groups = flatten([
    for account_key, account in var.account_assignments : [
      for principal_key, principal in account.groups : [
        for permissions_key, permissions in principal.permission_sets :
        {
          account             = local.account_map[account_key]
          permission_set_arn  = module.permission_sets.permission_sets[permissions].arn
          permission_set_name = module.permission_sets.permission_sets[permissions].name
          principal_name      = principal_key
          principal_type      = "GROUP"
        }
      ]
    ] if lookup(account, "groups", null) != null
  ])
  account_assignments_users = flatten([
    for account_key, account in var.account_assignments : [
      for principal_key, principal in account.users : [
        for permissions_key, permissions in principal.permission_sets :
        {
          account             = local.account_map[account_key]
          permission_set_arn  = module.permission_sets.permission_sets[permissions].arn
          permission_set_name = module.permission_sets.permission_sets[permissions].name
          principal_name      = principal_key
          principal_type      = "USER"
        }
      ]
    ] if lookup(account, "users", null) != null
  ])

  account_assignments = concat(local.account_assignments_groups, local.account_assignments_users)

  # Merged display_name → group_id map for the sso_account_assignments submodule.
  # Resolving IDs here (instead of inside the submodule's data source) means
  # plan succeeds even when a Terraform-managed group has not yet been
  # created. Manual groups contribute group_id from aws_identitystore_group.manual
  # (known-after-apply on first plan, stable thereafter); IdP groups contribute
  # IDs from the data source (always succeeds for SCIM-synced groups).
  # Requires terraform-aws-sso >= <next release with var.group_ids>.
  all_group_ids = merge(
    { for k, v in aws_identitystore_group.manual : k => v.group_id },
    { for k, v in data.aws_identitystore_group.idp : k => v.group_id },
  )

  all_user_names = distinct(flatten([
    for account_key, account in var.account_assignments : [
      for user_key, user in lookup(account, "users", {}) : user_key
    ]
  ]))

  aws_partition = data.aws_partition.current.partition
}

data "aws_ssoadmin_instances" "this" {}

data "aws_partition" "current" {}

resource "aws_identitystore_group" "manual" {
  for_each = toset(var.groups)

  display_name = each.key
  description  = "Group created with Terraform"

  identity_store_id = tolist(data.aws_ssoadmin_instances.this.identity_store_ids)[0]
}

data "aws_identitystore_user" "this" {
  for_each = toset(local.all_user_names)

  identity_store_id = tolist(data.aws_ssoadmin_instances.this.identity_store_ids)[0]

  alternate_identifier {
    unique_attribute {
      attribute_path  = "UserName"
      attribute_value = each.key
    }
  }
}

# Look up IdP-managed groups (synced from Google Workspace, Okta, etc.)
data "aws_identitystore_group" "idp" {
  for_each = toset(var.idp_groups)

  identity_store_id = tolist(data.aws_ssoadmin_instances.this.identity_store_ids)[0]

  alternate_identifier {
    unique_attribute {
      attribute_path  = "DisplayName"
      attribute_value = each.key
    }
  }
}

module "permission_sets" {
  source  = "cloudposse/sso/aws//modules/permission-sets"
  version = "1.2.0"

  permission_sets = concat(
    local.overridable_additional_permission_sets,
    local.administrator_access_permission_set,
    local.billing_administrator_access_permission_set,
    local.billing_read_only_access_permission_set,
    local.dns_administrator_access_permission_set,
    local.poweruser_access_permission_set,
    local.read_only_access_permission_set,
    local.root_access_permission_set,
    local.terraform_plan_access_permission_set,
    local.terraform_apply_access_permission_set,
    local.terraform_state_access_permission_set,
    local.terraform_plan_access_additional_permission_sets,
    local.terraform_apply_access_additional_permission_sets,
    local.terraform_state_access_additional_permission_sets,
  )

  context = module.this.context
}

module "sso_account_assignments" {
  source  = "cloudposse/sso/aws//modules/account-assignments"
  version = "1.2.1"

  account_assignments = local.account_assignments
  group_ids           = local.all_group_ids
  context             = module.this.context
}
