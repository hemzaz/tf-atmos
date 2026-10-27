locals {
  enabled      = module.this.enabled
  account_name = module.this.name
}

resource "aws_organizations_account" "this" {
  count = local.enabled ? 1 : 0

  name                       = local.account_name
  email                      = var.account_email
  parent_id                  = var.parent_id
  iam_user_access_to_billing = var.iam_user_access_to_billing
  close_on_deletion          = var.close_on_deletion
  create_govcloud            = var.create_govcloud
  role_name                  = var.role_name
  tags                       = merge(module.this.tags, { Name = local.account_name })

  lifecycle {
    ignore_changes = [iam_user_access_to_billing, role_name]
  }
}
