# Default providers.tf for use without the account-map component.
# If your infrastructure uses account-map for dynamic account resolution,
# vendor the v1-providers.tf mixin instead, which replaces this file.

variable "account_map_enabled" {
  type        = bool
  description = <<-EOT
    When true, uses the account-map component to look up account IDs dynamically.
    When false, uses the static account_map variable instead. Set to false when
    using Atmos Auth profiles and static account mappings.
    EOT
  default     = false
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
  description = "Map of account names (tenant-stage format) to account IDs. Used to verify we're targeting the correct AWS account. Optional attributes support component-specific functionality (e.g., audit_account_account_name for cloudtrail, root_account_account_name for aws-sso)."
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
}

# Dummy module to satisfy references from optional mixin files that use
# module.iam_roles (e.g. remote-state.tf).
# When using account-map, vendor the v1-providers.tf mixin which replaces
# this with the real iam-roles module.
module "iam_roles" {
  source  = "cloudposse/label/null"
  version = "0.25.0"

  context = module.this.context
}
