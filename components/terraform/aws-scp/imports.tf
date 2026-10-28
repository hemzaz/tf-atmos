variable "import_policy_id" {
  type        = string
  description = "The ID of an existing SCP to import"
  default     = null
}

variable "import_target_ids" {
  type        = list(string)
  description = "The IDs of the targets (organization roots, OUs, or accounts) that already have the SCP attached, to import existing attachments. Must be a subset of target_ids."
  default     = []
}

import {
  for_each = var.import_policy_id != null && local.enabled ? toset([var.import_policy_id]) : toset([])
  to       = aws_organizations_policy.this[0]
  id       = each.value
}

import {
  for_each = var.import_policy_id != null && local.enabled ? toset(var.import_target_ids) : toset([])
  to       = aws_organizations_policy_attachment.this[each.value]
  id       = "${each.value}:${var.import_policy_id}"
}
