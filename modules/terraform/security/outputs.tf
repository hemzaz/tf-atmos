# Security module outputs

# KMS Key outputs
output "kms_key_id" {
  description = "ID of the KMS key"
  value       = var.create_kms_key ? aws_kms_key.main[0].id : ""
}

output "kms_key_arn" {
  description = "ARN of the KMS key"
  value       = var.create_kms_key ? aws_kms_key.main[0].arn : ""
}

output "kms_key_alias" {
  description = "Alias of the KMS key"
  value       = var.create_kms_key ? aws_kms_alias.main[0].name : ""
}

output "kms_key_alias_arn" {
  description = "ARN of the KMS key alias"
  value       = var.create_kms_key ? aws_kms_alias.main[0].arn : ""
}

# Security Group outputs
output "security_group_id" {
  description = "ID of the security group"
  value       = var.create_security_group ? aws_security_group.main[0].id : ""
}

output "security_group_arn" {
  description = "ARN of the security group"
  value       = var.create_security_group ? aws_security_group.main[0].arn : ""
}

output "security_group_name" {
  description = "Name of the security group"
  value       = var.create_security_group ? aws_security_group.main[0].name : ""
}

# IAM Role outputs
output "service_role_arn" {
  description = "ARN of the service role"
  value       = var.create_service_role ? aws_iam_role.service_role[0].arn : ""
}

output "service_role_name" {
  description = "Name of the service role"
  value       = var.create_service_role ? aws_iam_role.service_role[0].name : ""
}

output "service_role_unique_id" {
  description = "Unique ID of the service role"
  value       = var.create_service_role ? aws_iam_role.service_role[0].unique_id : ""
}

# Custom IAM Policy outputs
output "custom_policy_arn" {
  description = "ARN of the custom IAM policy"
  value       = var.create_custom_policy && length(var.custom_policy_statements) > 0 ? aws_iam_policy.custom[0].arn : ""
}

output "custom_policy_name" {
  description = "Name of the custom IAM policy"
  value       = var.create_custom_policy && length(var.custom_policy_statements) > 0 ? aws_iam_policy.custom[0].name : ""
}

# CloudWatch Log Group outputs
output "log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = var.create_log_group ? aws_cloudwatch_log_group.security_logs[0].name : ""
}

output "log_group_arn" {
  description = "ARN of the CloudWatch log group"
  value       = var.create_log_group ? aws_cloudwatch_log_group.security_logs[0].arn : ""
}

# S3 Bucket Policy outputs
output "s3_bucket_policy_json" {
  description = "S3 bucket policy JSON document"
  value       = var.create_s3_bucket_policy ? data.aws_iam_policy_document.s3_bucket_policy[0].json : ""
}

# WAF outputs
output "waf_web_acl_id" {
  description = "ID of the WAF Web ACL"
  value       = var.create_waf_web_acl ? aws_wafv2_web_acl.main[0].id : ""
}

output "waf_web_acl_arn" {
  description = "ARN of the WAF Web ACL"
  value       = var.create_waf_web_acl ? aws_wafv2_web_acl.main[0].arn : ""
}

output "waf_web_acl_name" {
  description = "Name of the WAF Web ACL"
  value       = var.create_waf_web_acl ? aws_wafv2_web_acl.main[0].name : ""
}

# Common module outputs (pass-through)
output "name_prefix" {
  description = "Name prefix from common module"
  value       = module.common.name_prefix
}

output "component_name" {
  description = "Component name from common module"
  value       = module.common.component_name
}

output "common_tags" {
  description = "Common tags from common module"
  value       = module.common.common_tags
}

# Security baseline configuration
output "security_baseline" {
  description = "Security baseline configuration"
  value = {
    kms_key_arn              = var.create_kms_key ? aws_kms_key.main[0].arn : var.existing_kms_key_arn
    encryption_at_rest       = var.create_kms_key || var.existing_kms_key_arn != ""
    key_rotation_enabled     = var.enable_key_rotation
    multi_region_key         = var.enable_multi_region_key
    security_group_id        = var.create_security_group ? aws_security_group.main[0].id : ""
    service_role_arn         = var.create_service_role ? aws_iam_role.service_role[0].arn : ""
    log_group_name           = var.create_log_group ? aws_cloudwatch_log_group.security_logs[0].name : ""
    waf_web_acl_arn         = var.create_waf_web_acl ? aws_wafv2_web_acl.main[0].arn : ""
  }
}

# Compliance information
output "compliance_status" {
  description = "Compliance status and features enabled"
  value = {
    data_classification      = var.data_classification
    compliance_frameworks    = var.compliance_frameworks
    encryption_at_rest      = var.create_kms_key || var.existing_kms_key_arn != ""
    key_rotation_enabled    = var.enable_key_rotation
    secure_transport_only   = var.create_s3_bucket_policy
    access_logging_enabled  = var.create_log_group
    web_application_firewall = var.create_waf_web_acl
    rate_limiting_enabled   = var.enable_rate_limiting
    geo_blocking_enabled    = length(var.blocked_countries) > 0
    cross_account_denial    = var.deny_cross_account_access
  }
}

# Resource ARNs for cross-references
output "resource_arns" {
  description = "ARNs of all created resources"
  value = {
    kms_key        = var.create_kms_key ? aws_kms_key.main[0].arn : ""
    security_group = var.create_security_group ? aws_security_group.main[0].arn : ""
    service_role   = var.create_service_role ? aws_iam_role.service_role[0].arn : ""
    custom_policy  = var.create_custom_policy && length(var.custom_policy_statements) > 0 ? aws_iam_policy.custom[0].arn : ""
    log_group      = var.create_log_group ? aws_cloudwatch_log_group.security_logs[0].arn : ""
    waf_web_acl    = var.create_waf_web_acl ? aws_wafv2_web_acl.main[0].arn : ""
  }
}

# Security recommendations
output "security_recommendations" {
  description = "Security recommendations based on current configuration"
  value = {
    enable_key_rotation = !var.enable_key_rotation && var.create_kms_key ? "Consider enabling KMS key rotation for enhanced security" : null
    use_multi_region_key = !var.enable_multi_region_key && var.environment == "prod" ? "Consider using multi-region KMS key for disaster recovery" : null
    enable_waf = !var.create_waf_web_acl ? "Consider enabling WAF for web application protection" : null
    restrict_cidr_blocks = var.create_security_group && length(flatten([for rule in var.ingress_rules : rule.cidr_blocks if contains(rule.cidr_blocks, "0.0.0.0/0")])) > 0 ? "Avoid using 0.0.0.0/0 in security group rules" : null
    enable_logging = !var.create_log_group ? "Consider enabling CloudWatch logging for security monitoring" : null
  }
}