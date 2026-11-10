output "delegated_administrator_account_id" {
  value       = local.org_delegated_administrator_account_id
  description = "The AWS Account ID of the AWS Organization delegated administrator account"
}

output "sns_topic_name" {
  value       = local.create_securityhub ? try(module.security_hub[0].sns_topic.name, null) : null
  description = "The name of the SNS topic created by the component"
}

output "sns_topic_subscriptions" {
  value       = local.create_securityhub ? try(module.security_hub[0].sns_topic_subscriptions, null) : null
  description = "The SNS topic subscriptions created by the component"
}

output "product_subscriptions" {
  value = local.create_securityhub ? {
    for key, service in local.enabled_product_subscriptions :
    key => aws_securityhub_product_subscription.this[key].arn
  } : null
  description = "ARNs of Security Hub product subscriptions for AWS service integrations"
}
