# Enable product subscriptions to integrate findings from AWS security services
# These subscriptions allow Security Hub to receive findings from GuardDuty, Inspector, Macie, Config, etc.
# Product subscriptions are created in the delegated administrator account (security account)

locals {
  # Map of product subscription keys to their ARN service names
  # The key matches the variable field name, the value is the AWS product ARN suffix
  product_subscription_services = {
    guardduty        = "guardduty"
    inspector        = "inspector"
    macie            = "macie"
    config           = "config"
    access_analyzer  = "access-analyzer"
    firewall_manager = "firewall-manager"
  }

  # Filter to only enabled subscriptions
  enabled_product_subscriptions = {
    for key, service in local.product_subscription_services :
    key => service
    if local.create_securityhub && var.product_subscriptions[key]
  }
}

resource "aws_securityhub_product_subscription" "this" {
  for_each = local.enabled_product_subscriptions

  product_arn = "arn:${one(data.aws_partition.this).partition}:securityhub:${one(data.aws_region.this).name}::product/aws/${each.value}"

  depends_on = [module.security_hub]
}
