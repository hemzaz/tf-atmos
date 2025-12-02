##############################################
# State Machine Outputs
##############################################

output "state_machine_id" {
  description = "ID of the Step Functions state machine"
  value       = aws_sfn_state_machine.main.id
}

output "state_machine_arn" {
  description = "ARN of the Step Functions state machine"
  value       = aws_sfn_state_machine.main.arn
}

output "state_machine_name" {
  description = "Name of the Step Functions state machine"
  value       = aws_sfn_state_machine.main.name
}

output "state_machine_creation_date" {
  description = "Creation date of the state machine"
  value       = aws_sfn_state_machine.main.creation_date
}

output "state_machine_status" {
  description = "Status of the state machine"
  value       = aws_sfn_state_machine.main.status
}

##############################################
# IAM Role Outputs
##############################################

output "execution_role_arn" {
  description = "ARN of the state machine execution role"
  value       = aws_iam_role.state_machine.arn
}

output "execution_role_name" {
  description = "Name of the state machine execution role"
  value       = aws_iam_role.state_machine.name
}

##############################################
# CloudWatch Logs Outputs
##############################################

output "log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = var.enable_logging ? aws_cloudwatch_log_group.main[0].name : null
}

output "log_group_arn" {
  description = "ARN of the CloudWatch log group"
  value       = var.enable_logging ? aws_cloudwatch_log_group.main[0].arn : null
}

##############################################
# CloudWatch Alarm Outputs
##############################################

output "alarm_execution_failed_arn" {
  description = "ARN of the execution failed alarm"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.execution_failed[0].arn : null
}

output "alarm_execution_throttled_arn" {
  description = "ARN of the execution throttled alarm"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.execution_throttled[0].arn : null
}

output "alarm_execution_timed_out_arn" {
  description = "ARN of the execution timed out alarm"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.execution_timed_out[0].arn : null
}
