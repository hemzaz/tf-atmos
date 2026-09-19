locals {
  web_acl_name = "${var.name_prefix}-waf"

  common_tags = merge(
    var.tags,
    {
      ManagedBy = "Terraform"
      Module    = "waf-advanced"
    }
  )

  # Geo rule: an allow list (block everything else) wins over a block list
  geo_block_mode       = length(var.geo_allow_countries) > 0 ? "allow" : "block"
  geo_countries        = local.geo_block_mode == "allow" ? var.geo_allow_countries : var.geo_block_countries
  geo_blocking_enabled = var.enable_geo_blocking && length(local.geo_countries) > 0

  # Logging destinations. WAF requires names prefixed with "aws-waf-logs-".
  use_existing_log_destination = var.log_destination_arn != ""
  create_s3_bucket             = var.enable_logging && var.log_destination_type == "s3" && !local.use_existing_log_destination
  create_cloudwatch_log_group  = var.enable_logging && var.log_destination_type == "cloudwatch" && !local.use_existing_log_destination
  s3_bucket_name               = "aws-waf-logs-${var.name_prefix}-${data.aws_caller_identity.current.account_id}"
  log_group_name               = "aws-waf-logs-${var.name_prefix}"

  log_destination_arn_computed = (
    local.use_existing_log_destination ? var.log_destination_arn :
    local.create_s3_bucket ? aws_s3_bucket.waf_logs[0].arn :
    local.create_cloudwatch_log_group ? aws_cloudwatch_log_group.waf_logs[0].arn :
    null
  )

  # Rule priorities: cheapest rules are evaluated first
  priority_rate_limit       = 10
  priority_geo_blocking     = 20
  priority_ip_reputation    = 30
  priority_anonymous_ip     = 40
  priority_known_bad_inputs = 50
  priority_core_rule_set    = 60
  priority_sql_database     = 70
  priority_linux_os         = 80
  priority_unix_os          = 90
  priority_windows_os       = 100
  priority_php_app          = 110
  priority_wordpress        = 120
  priority_bot_control      = 130

  enabled_managed_rule_priorities = [
    for p, enabled in {
      (local.priority_rate_limit)       = var.enable_rate_limiting
      (local.priority_geo_blocking)     = local.geo_blocking_enabled
      (local.priority_ip_reputation)    = var.enable_ip_reputation
      (local.priority_anonymous_ip)     = var.enable_anonymous_ip_list
      (local.priority_known_bad_inputs) = var.enable_known_bad_inputs
      (local.priority_core_rule_set)    = var.enable_core_rule_set
      (local.priority_sql_database)     = var.enable_sql_database_protection
      (local.priority_linux_os)         = var.enable_linux_os_protection
      (local.priority_unix_os)          = var.enable_unix_os_protection
      (local.priority_windows_os)       = var.enable_windows_os_protection
      (local.priority_php_app)          = var.enable_php_application_protection
      (local.priority_wordpress)        = var.enable_wordpress_protection
      (local.priority_bot_control)      = var.enable_bot_control
    } : tonumber(p) if enabled
  ]
}
