locals {
  poweruser_access_permission_set = local.enabled ? [{
    name             = "PowerUserAccess",
    description      = "Allow Poweruser access to the account",
    relay_state      = "",
    session_duration = var.session_duration,
    tags             = module.this.tags,
    inline_policy    = ""
    policy_attachments = [
      "arn:${local.aws_partition}:iam::aws:policy/PowerUserAccess",
      "arn:${local.aws_partition}:iam::aws:policy/AWSSupportAccess",
    ]
    customer_managed_policy_attachments = []
  }] : []
}
