##############################################
# Topic Outputs
##############################################

output "topic_id" {
  description = "ID of the SNS topic"
  value       = aws_sns_topic.main.id
}

output "topic_arn" {
  description = "ARN of the SNS topic"
  value       = aws_sns_topic.main.arn
}

output "topic_name" {
  description = "Name of the SNS topic"
  value       = aws_sns_topic.main.name
}

##############################################
# KMS Key Outputs
##############################################

output "kms_key_id" {
  description = "ID of the KMS key used for encryption"
  value       = local.kms_key_id
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for encryption"
  value       = var.enable_encryption && var.kms_key_id == null ? aws_kms_key.topic[0].arn : var.kms_key_id
}

##############################################
# Subscription Outputs
##############################################

output "sqs_subscription_arns" {
  description = "ARNs of SQS subscriptions"
  value       = { for k, v in aws_sns_topic_subscription.sqs : k => v.arn }
}

output "lambda_subscription_arns" {
  description = "ARNs of Lambda subscriptions"
  value       = { for k, v in aws_sns_topic_subscription.lambda : k => v.arn }
}

output "http_subscription_arns" {
  description = "ARNs of HTTP subscriptions"
  value       = { for k, v in aws_sns_topic_subscription.http : k => v.arn }
}

output "email_subscription_arns" {
  description = "ARNs of email subscriptions"
  value       = { for k, v in aws_sns_topic_subscription.email : k => v.arn }
}

##############################################
# CloudWatch Alarm Outputs
##############################################

output "alarm_publish_failed_arn" {
  description = "ARN of the message publish failed alarm"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.message_publish_failed[0].arn : null
}
