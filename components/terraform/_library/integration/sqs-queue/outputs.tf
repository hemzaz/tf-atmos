##############################################
# Queue Outputs
##############################################

output "queue_id" {
  description = "ID of the SQS queue"
  value       = aws_sqs_queue.main.id
}

output "queue_arn" {
  description = "ARN of the SQS queue"
  value       = aws_sqs_queue.main.arn
}

output "queue_url" {
  description = "URL of the SQS queue"
  value       = aws_sqs_queue.main.url
}

output "queue_name" {
  description = "Name of the SQS queue"
  value       = aws_sqs_queue.main.name
}

##############################################
# Dead Letter Queue Outputs
##############################################

output "dlq_id" {
  description = "ID of the dead letter queue"
  value       = var.enable_dead_letter_queue ? aws_sqs_queue.dlq[0].id : null
}

output "dlq_arn" {
  description = "ARN of the dead letter queue"
  value       = var.enable_dead_letter_queue ? aws_sqs_queue.dlq[0].arn : null
}

output "dlq_url" {
  description = "URL of the dead letter queue"
  value       = var.enable_dead_letter_queue ? aws_sqs_queue.dlq[0].url : null
}

output "dlq_name" {
  description = "Name of the dead letter queue"
  value       = var.enable_dead_letter_queue ? aws_sqs_queue.dlq[0].name : null
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
  value       = var.enable_encryption && var.kms_key_id == null ? aws_kms_key.queue[0].arn : var.kms_key_id
}

##############################################
# CloudWatch Alarm Outputs
##############################################

output "alarm_queue_depth_arn" {
  description = "ARN of the queue depth alarm"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.queue_depth[0].arn : null
}

output "alarm_message_age_arn" {
  description = "ARN of the message age alarm"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.age_of_oldest_message[0].arn : null
}

output "alarm_dlq_messages_arn" {
  description = "ARN of the DLQ messages alarm"
  value       = var.enable_cloudwatch_alarms && var.enable_dead_letter_queue ? aws_cloudwatch_metric_alarm.dlq_messages[0].arn : null
}
