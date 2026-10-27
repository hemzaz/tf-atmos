variable "import_resource_id" {
  type        = string
  description = "The ID of an existing AWS Organization to import. If set, the organization will be imported rather than created."
  default     = null
}

import {
  for_each = var.import_resource_id != null && var.enabled != false ? toset([var.import_resource_id]) : toset([])
  to       = aws_organizations_organization.this[0]
  id       = each.value
}
