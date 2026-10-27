variable "import_account_id" {
  type        = string
  description = "The AWS account ID to import. Set this to import an existing account into Terraform state."
  default     = null
}

import {
  for_each = var.import_account_id != null && var.enabled != false ? toset([var.import_account_id]) : toset([])
  to       = aws_organizations_account.this[0]
  id       = each.value
}
