output "delegated_administrator_account_id" {
  value       = local.org_delegated_administrator_account_id
  description = "The AWS Account ID of the AWS Organization delegated administrator account"
}

# Outputs for locally created detector (when this account is the delegated admin)
output "guardduty_detector_arn" {
  value       = local.create_guardduty_collector ? try(module.guardduty[0].guardduty_detector.arn, null) : null
  description = "The ARN of the GuardDuty detector created by the component in this account"
}

output "guardduty_detector_id" {
  value       = local.create_guardduty_collector ? try(module.guardduty[0].guardduty_detector.id, null) : null
  description = "The ID of the GuardDuty detector created by the component in this account"
}

# Outputs for remote state detector (when referencing the delegated admin detector)
output "guardduty_delegated_detector_arn" {
  value       = local.create_org_configuration ? try(module.guardduty_delegated_detector[0].outputs.guardduty_detector_arn, null) : null
  description = "The ARN of the GuardDuty detector from the delegated administrator account (via remote state)"
}

output "guardduty_delegated_detector_id" {
  value       = local.create_org_configuration ? try(module.guardduty_delegated_detector[0].outputs.guardduty_detector_id, null) : null
  description = "The ID of the GuardDuty detector from the delegated administrator account (via remote state)"
}

# Outputs for SNS topic
output "sns_topic_name" {
  value       = local.create_sns_topic ? try(module.sns_topic[0].sns_topic.name, null) : null
  description = "The name of the SNS topic created for GuardDuty findings"
}

output "sns_topic_subscriptions" {
  value       = local.create_sns_topic ? try(module.sns_topic[0].aws_sns_topic_subscriptions, null) : null
  description = "The SNS topic subscriptions for GuardDuty findings"
}

# Outputs for root-level SNS/SQS/KMS resources
output "root_sns_topic_arn" {
  value       = local.create_sns_topic ? try(module.sns_topic[0].sns_topic.arn, null) : null
  description = "The ARN of the root-level SNS topic created for GuardDuty findings"
}

output "root_sns_topic_name" {
  value       = local.create_sns_topic ? try(module.sns_topic[0].sns_topic.name, null) : null
  description = "The name of the root-level SNS topic created for GuardDuty findings"
}

output "root_sns_topic_id" {
  value       = local.create_sns_topic ? try(module.sns_topic[0].sns_topic.id, null) : null
  description = "The ID of the root-level SNS topic created for GuardDuty findings"
}

output "root_sqs_queue_arn" {
  value       = local.sqs_enabled ? try(module.sqs[0].queue_arn, null) : null
  description = "The ARN of the SQS queue subscribed to the GuardDuty SNS topic"
}

output "root_sqs_queue_name" {
  value       = local.sqs_enabled ? try(module.sqs[0].queue_name, null) : null
  description = "The name of the SQS queue subscribed to the GuardDuty SNS topic"
}

output "root_sqs_queue_url" {
  value       = local.sqs_enabled ? try(module.sqs[0].queue_url, null) : null
  description = "The URL of the SQS queue subscribed to the GuardDuty SNS topic"
}

output "root_kms_key_arn" {
  value       = local.create_sns_topic ? try(module.kms_key[0].key_arn, null) : null
  description = "The ARN of the KMS key used for encrypting the GuardDuty SNS topic"
}

output "root_kms_key_id" {
  value       = local.create_sns_topic ? try(module.kms_key[0].key_id, null) : null
  description = "The ID of the KMS key used for encrypting the GuardDuty SNS topic"
}

output "root_kms_key_alias" {
  value       = local.create_sns_topic ? try(module.kms_key[0].alias_name, null) : null
  description = "The alias of the KMS key used for encrypting the GuardDuty SNS topic"
}

output "cloudwatch_event_rule_arn" {
  value       = local.enable_cloudwatch ? try(aws_cloudwatch_event_rule.findings[0].arn, null) : null
  description = "The ARN of the CloudWatch Event Rule for GuardDuty findings"
}

output "cloudwatch_event_rule_id" {
  value       = local.enable_cloudwatch ? try(aws_cloudwatch_event_rule.findings[0].id, null) : null
  description = "The ID of the CloudWatch Event Rule for GuardDuty findings"
}
