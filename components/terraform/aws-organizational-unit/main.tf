locals {
  enabled                  = module.this.enabled
  organizational_unit_name = module.this.name
}

resource "aws_organizations_organizational_unit" "this" {
  count = local.enabled ? 1 : 0

  name      = local.organizational_unit_name
  parent_id = var.parent_id
  tags      = module.this.tags
}
