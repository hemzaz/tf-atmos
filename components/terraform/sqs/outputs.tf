# Cloud Posse's component returns the whole terraform-aws-modules/sqs module as
# one `sqs_queue` object; these are that module's output names, flattened.

output "queue_id" {
  description = "The URL of the queue (SQS uses the URL as the queue ID)"
  value       = one(aws_sqs_queue.this[*].id)
}

output "queue_arn" {
  description = "The ARN of the queue"
  value       = one(aws_sqs_queue.this[*].arn)
}

output "queue_name" {
  description = "The name of the queue"
  value       = one(aws_sqs_queue.this[*].name)
}

output "queue_url" {
  description = "The URL of the queue"
  value       = one(aws_sqs_queue.this[*].url)
}

output "dead_letter_queue_id" {
  description = "The URL of the dead-letter queue (null unless dlq_enabled)"
  value       = one(aws_sqs_queue.dlq[*].id)
}

output "dead_letter_queue_arn" {
  description = "The ARN of the dead-letter queue (null unless dlq_enabled)"
  value       = one(aws_sqs_queue.dlq[*].arn)
}

output "dead_letter_queue_name" {
  description = "The name of the dead-letter queue (null unless dlq_enabled)"
  value       = one(aws_sqs_queue.dlq[*].name)
}

output "dead_letter_queue_url" {
  description = "The URL of the dead-letter queue (null unless dlq_enabled)"
  value       = one(aws_sqs_queue.dlq[*].url)
}
