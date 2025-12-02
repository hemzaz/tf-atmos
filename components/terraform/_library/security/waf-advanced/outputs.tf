##############################################
# WAF Web ACL Outputs
##############################################

output "web_acl_id" {
  description = <<-EOT
    The ID of the WAF Web ACL.
    Use this to reference the Web ACL in other resources.
  EOT
  value       = aws_wafv2_web_acl.main.id
}

output "web_acl_arn" {
  description = <<-EOT
    The ARN of the WAF Web ACL.
    Use this to associate the Web ACL with CloudFront, ALB, API Gateway, or other resources.
    Example: arn:aws:wafv2:us-east-1:123456789012:regional/webacl/example/a1b2c3d4
  EOT
  value       = aws_wafv2_web_acl.main.arn
}

output "web_acl_name" {
  description = <<-EOT
    The name of the WAF Web ACL.
  EOT
  value       = aws_wafv2_web_acl.main.name
}

output "web_acl_capacity" {
  description = <<-EOT
    The capacity units consumed by the Web ACL.
    AWS WAF has a limit of 1500 WCUs (Web ACL Capacity Units) per Web ACL.
    Monitor this value to ensure you don't exceed the limit.
  EOT
  value       = aws_wafv2_web_acl.main.capacity
}

##############################################
# Logging Outputs
##############################################

output "log_destination_arn" {
  description = <<-EOT
    The ARN of the log destination (S3 bucket or CloudWatch log group).
    Empty if logging is disabled.
  EOT
  value       = var.enable_logging ? local.log_destination_arn_computed : ""
}

output "s3_bucket_name" {
  description = <<-EOT
    The name of the S3 bucket used for WAF logs.
    Empty if S3 logging is not enabled or an existing bucket is used.
  EOT
  value       = local.create_s3_bucket ? aws_s3_bucket.waf_logs[0].id : ""
}

output "s3_bucket_arn" {
  description = <<-EOT
    The ARN of the S3 bucket used for WAF logs.
    Empty if S3 logging is not enabled or an existing bucket is used.
  EOT
  value       = local.create_s3_bucket ? aws_s3_bucket.waf_logs[0].arn : ""
}

output "cloudwatch_log_group_name" {
  description = <<-EOT
    The name of the CloudWatch log group used for WAF logs.
    Empty if CloudWatch logging is not enabled or an existing log group is used.
  EOT
  value       = local.create_cloudwatch_log_group ? aws_cloudwatch_log_group.waf_logs[0].name : ""
}

output "cloudwatch_log_group_arn" {
  description = <<-EOT
    The ARN of the CloudWatch log group used for WAF logs.
    Empty if CloudWatch logging is not enabled or an existing log group is used.
  EOT
  value       = local.create_cloudwatch_log_group ? aws_cloudwatch_log_group.waf_logs[0].arn : ""
}

##############################################
# Configuration Summary
##############################################

output "enabled_rules_summary" {
  description = <<-EOT
    Summary of enabled WAF rules for documentation and auditing purposes.
  EOT
  value = {
    rate_limiting            = var.enable_rate_limiting
    geo_blocking             = local.geo_blocking_enabled
    ip_reputation            = var.enable_ip_reputation
    anonymous_ip             = var.enable_anonymous_ip_list
    known_bad_inputs         = var.enable_known_bad_inputs
    core_rule_set            = var.enable_core_rule_set
    sql_database_protection  = var.enable_sql_database_protection
    linux_os_protection      = var.enable_linux_os_protection
    unix_os_protection       = var.enable_unix_os_protection
    windows_os_protection    = var.enable_windows_os_protection
    php_application          = var.enable_php_application_protection
    wordpress_protection     = var.enable_wordpress_protection
    bot_control              = var.enable_bot_control
    custom_rules_count       = length(var.custom_rules)
  }
}

output "cost_estimate_monthly" {
  description = <<-EOT
    Estimated monthly cost breakdown for the WAF configuration (in USD).
    Note: This is an estimate based on standard pricing and assumes moderate traffic.
    Actual costs will vary based on request volume, enabled features, and region.
  EOT
  value = {
    web_acl_base              = 5
    managed_rules             = (var.enable_core_rule_set ? 1 : 0) + (var.enable_known_bad_inputs ? 1 : 0) + (var.enable_sql_database_protection ? 1 : 0) + (var.enable_linux_os_protection ? 1 : 0) + (var.enable_unix_os_protection ? 1 : 0) + (var.enable_windows_os_protection ? 1 : 0) + (var.enable_php_application_protection ? 1 : 0) + (var.enable_wordpress_protection ? 1 : 0) + (var.enable_ip_reputation ? 1 : 0) + (var.enable_anonymous_ip_list ? 1 : 0)
    custom_rules              = length(var.custom_rules)
    bot_control_base          = var.enable_bot_control ? 10 : 0
    rate_limiting             = var.enable_rate_limiting ? 1 : 0
    geo_blocking              = local.geo_blocking_enabled ? 1 : 0
    estimated_total_base      = 5 + (var.enable_core_rule_set ? 1 : 0) + (var.enable_known_bad_inputs ? 1 : 0) + (var.enable_sql_database_protection ? 1 : 0) + (var.enable_linux_os_protection ? 1 : 0) + (var.enable_unix_os_protection ? 1 : 0) + (var.enable_windows_os_protection ? 1 : 0) + (var.enable_php_application_protection ? 1 : 0) + (var.enable_wordpress_protection ? 1 : 0) + (var.enable_ip_reputation ? 1 : 0) + (var.enable_anonymous_ip_list ? 1 : 0) + length(var.custom_rules) + (var.enable_bot_control ? 10 : 0) + (var.enable_rate_limiting ? 1 : 0) + (local.geo_blocking_enabled ? 1 : 0)
    note                      = "Plus $0.60 per 1M requests (standard), $1.00 per 1M requests (bot control), and logging storage costs"
  }
}

##############################################
# Resource Associations
##############################################

output "associated_resource_arns" {
  description = <<-EOT
    List of resource ARNs associated with this Web ACL.
  EOT
  value       = var.resource_arns
}

output "association_count" {
  description = <<-EOT
    Number of resources associated with this Web ACL.
  EOT
  value       = length(var.resource_arns)
}

##############################################
# Monitoring
##############################################

output "cloudwatch_metrics" {
  description = <<-EOT
    CloudWatch metrics configuration for monitoring WAF activity.
    Use these metric names in CloudWatch dashboards and alarms.
  EOT
  value = {
    web_acl_metric      = local.web_acl_name
    namespace           = "AWS/WAFV2"
    dashboard_url       = "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#metricsV2:graph=~();query=~'*7bAWS*2fWAFV2*2cRegion*2cRule*2cWebACL*7d*20${local.web_acl_name}"
    rate_limit_metric   = var.enable_rate_limiting ? "${var.name_prefix}-rate-limit" : ""
    bot_control_metric  = var.enable_bot_control ? "${var.name_prefix}-bot-control" : ""
    geo_blocking_metric = local.geo_blocking_enabled ? "${var.name_prefix}-geo-${local.geo_block_mode}" : ""
  }
}
