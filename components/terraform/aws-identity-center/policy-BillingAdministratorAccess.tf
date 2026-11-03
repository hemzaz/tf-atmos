locals {
  billing_administrator_access_permission_set = local.enabled ? [{
    name             = "BillingAdministratorAccess",
    description      = "Grants permissions for billing and cost management. This includes viewing account usage and viewing and modifying budgets and payment methods.",
    relay_state      = "https://console.aws.amazon.com/billing/",
    session_duration = var.session_duration,
    tags             = module.this.tags,
    inline_policy    = ""
    policy_attachments = [
      "arn:${local.aws_partition}:iam::aws:policy/job-function/Billing",
      "arn:${local.aws_partition}:iam::aws:policy/AWSSupportAccess",
    ]
    customer_managed_policy_attachments = []
  }] : []
}
