variable "import_account_alias" {
  type        = string
  description = "Set to the existing IAM account alias to import it into Terraform state. Set to null after successful import."
  default     = null
}

import {
  for_each = var.import_account_alias != null && var.enabled != false ? toset([var.import_account_alias]) : toset([])
  to       = aws_iam_account_alias.this[0]
  id       = each.value
}
