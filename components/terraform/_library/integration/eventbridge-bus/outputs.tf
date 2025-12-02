##############################################
# Event Bus Outputs
##############################################

output "event_bus_name" {
  description = "Name of the EventBridge event bus"
  value       = aws_cloudwatch_event_bus.main.name
}

output "event_bus_arn" {
  description = "ARN of the EventBridge event bus"
  value       = aws_cloudwatch_event_bus.main.arn
}

##############################################
# Event Archive Outputs
##############################################

output "archive_arn" {
  description = "ARN of the event archive"
  value       = var.enable_archive ? aws_cloudwatch_event_archive.main["archive"].arn : null
}

output "archive_name" {
  description = "Name of the event archive"
  value       = var.enable_archive ? aws_cloudwatch_event_archive.main["archive"].name : null
}

##############################################
# Event Rules Outputs
##############################################

output "rule_arns" {
  description = "Map of rule names to ARNs"
  value       = { for k, v in aws_cloudwatch_event_rule.main : k => v.arn }
}

output "rule_names" {
  description = "Map of rule keys to names"
  value       = { for k, v in aws_cloudwatch_event_rule.main : k => v.name }
}

##############################################
# Schema Registry Outputs
##############################################

output "schema_registry_arn" {
  description = "ARN of the schema registry"
  value       = var.enable_schema_registry ? aws_schemas_registry.main[0].arn : null
}

output "schema_registry_name" {
  description = "Name of the schema registry"
  value       = var.enable_schema_registry ? aws_schemas_registry.main[0].name : null
}

output "schema_discoverer_id" {
  description = "ID of the schema discoverer"
  value       = var.enable_schema_discovery ? aws_schemas_discoverer.main[0].id : null
}

##############################################
# Target Outputs
##############################################

output "lambda_target_ids" {
  description = "Map of Lambda target IDs"
  value       = { for k, v in aws_cloudwatch_event_target.lambda : k => v.target_id }
}

output "sqs_target_ids" {
  description = "Map of SQS target IDs"
  value       = { for k, v in aws_cloudwatch_event_target.sqs : k => v.target_id }
}

output "step_functions_target_ids" {
  description = "Map of Step Functions target IDs"
  value       = { for k, v in aws_cloudwatch_event_target.step_functions : k => v.target_id }
}

##############################################
# CloudWatch Alarm Outputs
##############################################

output "alarm_failed_invocations_arn" {
  description = "ARN of the failed invocations alarm"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.failed_invocations[0].arn : null
}
