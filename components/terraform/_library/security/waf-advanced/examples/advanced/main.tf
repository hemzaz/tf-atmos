# Advanced WAF Example
# This example creates a comprehensive WAF with bot control, geo-blocking, and custom rules

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0, < 6.0.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Advanced WAF with all features
module "waf_advanced" {
  source = "../../"

  name_prefix = var.name_prefix
  scope       = "REGIONAL"

  # Full managed rule protection
  enable_core_rule_set             = true
  enable_known_bad_inputs          = true
  enable_sql_database_protection   = true
  enable_linux_os_protection       = true
  enable_ip_reputation             = true
  enable_anonymous_ip_list         = false  # Set to true if you want to block VPNs

  # Bot control with targeted detection (ML-based)
  enable_bot_control = var.enable_bot_control
  bot_control_level  = "TARGETED"

  # Aggressive rate limiting
  enable_rate_limiting = true
  rate_limit_per_ip    = 1000  # 1000 requests per 5 minutes
  rate_limit_window    = 300   # 5 minutes

  # Geo-blocking for high-risk countries
  enable_geo_blocking = var.enable_geo_blocking
  geo_block_countries = var.geo_block_countries

  # Custom rules
  custom_rules = [
    {
      name     = "block-admin-paths"
      priority = 100
      action   = "BLOCK"
      statement = {
        byte_match_statement = {
          positional_constraint = "STARTS_WITH"
          search_string         = "/admin"
          field_to_match = {
            uri_path = true
            body     = false
          }
          text_transformation = ["LOWERCASE"]
        }
        size_constraint_statement = null
      }
    },
    {
      name     = "block-api-admin"
      priority = 101
      action   = "BLOCK"
      statement = {
        byte_match_statement = {
          positional_constraint = "STARTS_WITH"
          search_string         = "/api/admin"
          field_to_match = {
            uri_path = true
            body     = false
          }
          text_transformation = ["LOWERCASE"]
        }
        size_constraint_statement = null
      }
    },
    {
      name     = "block-large-body"
      priority = 102
      action   = "BLOCK"
      statement = {
        byte_match_statement = null
        size_constraint_statement = {
          comparison_operator = "GT"
          size                = 8192  # 8KB
          field_to_match = {
            uri_path = false
            body     = true
          }
          text_transformation = ["NONE"]
        }
      }
    }
  ]

  # CloudWatch logging for better monitoring
  enable_logging       = true
  log_destination_type = "cloudwatch"
  log_retention_days   = 90

  # Associate with API Gateway or ALB
  resource_arns = var.resource_arns

  tags = {
    Environment = "production"
    Application = "api"
    Compliance  = "pci-dss"
    ManagedBy   = "terraform"
    Example     = "advanced"
    CostCenter  = "security"
  }
}

# CloudWatch Alarms for monitoring
resource "aws_cloudwatch_metric_alarm" "blocked_requests" {
  alarm_name          = "${var.name_prefix}-waf-blocked-requests"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "BlockedRequests"
  namespace           = "AWS/WAFV2"
  period              = "300"
  statistic           = "Sum"
  threshold           = "100"
  alarm_description   = "Alert when WAF blocks more than 100 requests in 5 minutes"
  treat_missing_data  = "notBreaching"

  dimensions = {
    WebACL = module.waf_advanced.web_acl_name
    Region = var.aws_region
    Rule   = "ALL"
  }

  tags = {
    Name        = "${var.name_prefix}-waf-blocked-requests"
    Environment = "production"
  }
}

resource "aws_cloudwatch_metric_alarm" "rate_limited_requests" {
  alarm_name          = "${var.name_prefix}-waf-rate-limited"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "BlockedRequests"
  namespace           = "AWS/WAFV2"
  period              = "300"
  statistic           = "Sum"
  threshold           = "50"
  alarm_description   = "Alert when rate limiting blocks requests"
  treat_missing_data  = "notBreaching"

  dimensions = {
    WebACL = module.waf_advanced.web_acl_name
    Region = var.aws_region
    Rule   = "${var.name_prefix}-rate-limit"
  }

  tags = {
    Name        = "${var.name_prefix}-waf-rate-limited"
    Environment = "production"
  }
}

# Outputs
output "web_acl_id" {
  description = "WAF Web ACL ID"
  value       = module.waf_advanced.web_acl_id
}

output "web_acl_arn" {
  description = "WAF Web ACL ARN"
  value       = module.waf_advanced.web_acl_arn
}

output "web_acl_capacity" {
  description = "WAF capacity units consumed"
  value       = module.waf_advanced.web_acl_capacity
}

output "cloudwatch_log_group" {
  description = "CloudWatch log group for WAF logs"
  value       = module.waf_advanced.cloudwatch_log_group_name
}

output "cost_estimate" {
  description = "Estimated monthly cost"
  value       = module.waf_advanced.cost_estimate_monthly
}

output "enabled_rules" {
  description = "Summary of enabled rules"
  value       = module.waf_advanced.enabled_rules_summary
}

output "cloudwatch_metrics" {
  description = "CloudWatch metrics configuration"
  value       = module.waf_advanced.cloudwatch_metrics
}

output "blocked_requests_alarm_arn" {
  description = "ARN of blocked requests alarm"
  value       = aws_cloudwatch_metric_alarm.blocked_requests.arn
}

output "rate_limited_alarm_arn" {
  description = "ARN of rate limited requests alarm"
  value       = aws_cloudwatch_metric_alarm.rate_limited_requests.arn
}
