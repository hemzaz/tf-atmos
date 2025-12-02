# Basic WAF Example
# This example creates a basic WAF with OWASP protection for an Application Load Balancer

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

# Basic WAF with OWASP Core Rule Set
module "waf_basic" {
  source = "../../"

  name_prefix = var.name_prefix
  scope       = "REGIONAL"

  # Enable basic OWASP protection
  enable_core_rule_set    = true
  enable_known_bad_inputs = true
  enable_ip_reputation    = true

  # Enable rate limiting to prevent abuse
  enable_rate_limiting = true
  rate_limit_per_ip    = 2000  # 2000 requests per 5 minutes
  rate_limit_window    = 300   # 5 minutes

  # Enable logging to S3 (auto-creates bucket)
  enable_logging       = true
  log_destination_type = "s3"
  log_retention_days   = 30

  # Associate with ALB (update with your ALB ARN)
  resource_arns = var.alb_arns

  tags = {
    Environment = "production"
    Application = "web"
    ManagedBy   = "terraform"
    Example     = "basic"
  }
}

# Outputs
output "web_acl_id" {
  description = "WAF Web ACL ID"
  value       = module.waf_basic.web_acl_id
}

output "web_acl_arn" {
  description = "WAF Web ACL ARN"
  value       = module.waf_basic.web_acl_arn
}

output "s3_bucket_name" {
  description = "S3 bucket for WAF logs"
  value       = module.waf_basic.s3_bucket_name
}

output "cost_estimate" {
  description = "Estimated monthly cost"
  value       = module.waf_basic.cost_estimate_monthly
}

output "enabled_rules" {
  description = "Summary of enabled rules"
  value       = module.waf_basic.enabled_rules_summary
}
