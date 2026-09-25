# Cloud Posse's aws-sns-topic output names. Upstream wires them crosswise
# (sns_topic_name returns the topic object, sns_topic_arn the ID); here each
# returns what its name says.

output "sns_topic_name" {
  description = "SNS topic name"
  value       = one(aws_sns_topic.this[*].name)
}

output "sns_topic_id" {
  description = "SNS topic ID (SNS uses the ARN as the ID)"
  value       = one(aws_sns_topic.this[*].id)
}

output "sns_topic_arn" {
  description = "SNS topic ARN"
  value       = one(aws_sns_topic.this[*].arn)
}

output "sns_topic_owner" {
  description = "SNS topic owner (account ID)"
  value       = one(aws_sns_topic.this[*].owner)
}

output "sns_topic_subscriptions" {
  description = "Subscription ARNs, keyed like subscribers"
  value       = { for k, s in aws_sns_topic_subscription.this : k => s.arn }
}
