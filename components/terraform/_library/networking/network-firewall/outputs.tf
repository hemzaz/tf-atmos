output "firewall_id" {
  description = "ID of the Network Firewall"
  value       = aws_networkfirewall_firewall.this.id
}

output "firewall_arn" {
  description = "ARN of the Network Firewall"
  value       = aws_networkfirewall_firewall.this.arn
}

output "firewall_policy_id" {
  description = "ID of the firewall policy"
  value       = aws_networkfirewall_firewall_policy.this.id
}

output "firewall_policy_arn" {
  description = "ARN of the firewall policy"
  value       = aws_networkfirewall_firewall_policy.this.arn
}

output "firewall_status" {
  description = "Nested list of firewall statuses"
  value       = aws_networkfirewall_firewall.this.firewall_status
}

output "firewall_endpoint_ids" {
  description = "List of firewall endpoint IDs"
  value = [
    for status in aws_networkfirewall_firewall.this.firewall_status[0].sync_states :
    status.attachment[0].endpoint_id
  ]
}

output "stateless_rule_group_arns" {
  description = "Map of stateless rule group ARNs"
  value       = { for k, v in aws_networkfirewall_rule_group.stateless : k => v.arn }
}

output "stateful_domain_rule_group_arns" {
  description = "Map of stateful domain rule group ARNs"
  value       = { for k, v in aws_networkfirewall_rule_group.stateful_domain : k => v.arn }
}

output "stateful_5tuple_rule_group_arns" {
  description = "Map of stateful 5-tuple rule group ARNs"
  value       = { for k, v in aws_networkfirewall_rule_group.stateful_5tuple : k => v.arn }
}

output "stateful_suricata_rule_group_arns" {
  description = "Map of stateful Suricata rule group ARNs"
  value       = { for k, v in aws_networkfirewall_rule_group.stateful_suricata : k => v.arn }
}

output "flow_logs_s3_bucket" {
  description = "S3 bucket name for flow logs"
  value       = var.enable_flow_logs_to_s3 ? aws_s3_bucket.flow_logs[0].id : null
}

output "flow_logs_cloudwatch_log_group" {
  description = "CloudWatch log group name for flow logs"
  value       = var.enable_flow_logs_to_cloudwatch ? aws_cloudwatch_log_group.flow_logs[0].name : null
}

output "alert_logs_cloudwatch_log_group" {
  description = "CloudWatch log group name for alert logs"
  value       = var.enable_alert_logs_to_cloudwatch ? aws_cloudwatch_log_group.alert_logs[0].name : null
}
