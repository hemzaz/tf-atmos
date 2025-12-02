output "default_sampling_rule_arn" {
  description = "ARN of the default sampling rule"
  value       = var.create_default_sampling_rule ? aws_xray_sampling_rule.default[0].arn : null
}

output "high_value_sampling_rule_arn" {
  description = "ARN of the high-value sampling rule"
  value       = var.enable_high_value_sampling ? aws_xray_sampling_rule.high_value[0].arn : null
}

output "custom_sampling_rule_arns" {
  description = "ARNs of custom sampling rules"
  value       = { for k, v in aws_xray_sampling_rule.custom : k => v.arn }
}

output "default_group_arn" {
  description = "ARN of the default X-Ray group"
  value       = var.create_default_group ? aws_xray_group.default[0].arn : null
}

output "error_group_arn" {
  description = "ARN of the error tracking group"
  value       = var.create_error_group ? aws_xray_group.errors[0].arn : null
}

output "slow_requests_group_arn" {
  description = "ARN of the slow requests group"
  value       = var.create_slow_requests_group ? aws_xray_group.slow_requests[0].arn : null
}

output "custom_group_arns" {
  description = "ARNs of custom X-Ray groups"
  value       = { for k, v in aws_xray_group.custom : k => v.arn }
}

output "trace_console_url" {
  description = "Console URL for X-Ray traces"
  value       = "https://console.aws.amazon.com/xray/home?region=${data.aws_region.current.name}#/traces"
}

output "service_map_url" {
  description = "Console URL for X-Ray service map"
  value       = "https://console.aws.amazon.com/xray/home?region=${data.aws_region.current.name}#/service-map"
}

output "sampling_rate" {
  description = "Effective sampling rate for the environment"
  value       = var.enable_cost_optimization ? local.sampling_rate : var.default_fixed_rate
}

output "estimated_monthly_cost" {
  description = "Estimated monthly cost based on sampling configuration"
  value       = "Varies by trace volume. ~$5 per 1M traces recorded and scanned."
}
