# Multi-Region WAF Example
# This example shows how to deploy WAF in multiple regions and for CloudFront

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0, < 6.0.0"
      configuration_aliases = [
        aws.us_east_1,
        aws.us_west_2,
        aws.eu_west_1
      ]
    }
  }
}

# CloudFront WAF (must be in us-east-1)
module "waf_cloudfront" {
  source = "../../"

  providers = {
    aws = aws.us_east_1
  }

  name_prefix = "${var.name_prefix}-cloudfront"
  scope       = "CLOUDFRONT"

  # CloudFront-optimized rules
  enable_core_rule_set    = true
  enable_known_bad_inputs = true
  enable_ip_reputation    = true
  enable_rate_limiting    = true
  rate_limit_per_ip       = 5000  # Higher limit for CDN

  # CloudFront logs to S3
  enable_logging       = true
  log_destination_type = "s3"
  log_retention_days   = 30

  resource_arns = var.cloudfront_distribution_arns

  tags = merge(var.tags, {
    Scope  = "cloudfront"
    Region = "global"
  })
}

# Regional WAF for US East 1 (ALB/API Gateway)
module "waf_us_east_1" {
  source = "../../"

  providers = {
    aws = aws.us_east_1
  }

  name_prefix = "${var.name_prefix}-use1"
  scope       = "REGIONAL"

  enable_core_rule_set    = true
  enable_known_bad_inputs = true
  enable_ip_reputation    = true
  enable_rate_limiting    = true
  rate_limit_per_ip       = 2000

  enable_logging       = true
  log_destination_type = "cloudwatch"
  log_retention_days   = 60

  resource_arns = var.us_east_1_resource_arns

  tags = merge(var.tags, {
    Region = "us-east-1"
  })
}

# Regional WAF for US West 2
module "waf_us_west_2" {
  source = "../../"

  providers = {
    aws = aws.us_west_2
  }

  name_prefix = "${var.name_prefix}-usw2"
  scope       = "REGIONAL"

  enable_core_rule_set    = true
  enable_known_bad_inputs = true
  enable_ip_reputation    = true
  enable_rate_limiting    = true
  rate_limit_per_ip       = 2000

  enable_logging       = true
  log_destination_type = "cloudwatch"
  log_retention_days   = 60

  resource_arns = var.us_west_2_resource_arns

  tags = merge(var.tags, {
    Region = "us-west-2"
  })
}

# Regional WAF for EU West 1
module "waf_eu_west_1" {
  source = "../../"

  providers = {
    aws = aws.eu_west_1
  }

  name_prefix = "${var.name_prefix}-euw1"
  scope       = "REGIONAL"

  enable_core_rule_set    = true
  enable_known_bad_inputs = true
  enable_ip_reputation    = true
  enable_rate_limiting    = true
  rate_limit_per_ip       = 2000

  # EU-specific geo-blocking
  enable_geo_blocking = var.enable_geo_blocking_eu
  geo_allow_countries = var.eu_allowed_countries

  enable_logging       = true
  log_destination_type = "cloudwatch"
  log_retention_days   = 90  # Longer retention for EU compliance

  resource_arns = var.eu_west_1_resource_arns

  tags = merge(var.tags, {
    Region     = "eu-west-1"
    Compliance = "gdpr"
  })
}

# Outputs
output "cloudfront_waf" {
  description = "CloudFront WAF configuration"
  value = {
    id         = module.waf_cloudfront.web_acl_id
    arn        = module.waf_cloudfront.web_acl_arn
    capacity   = module.waf_cloudfront.web_acl_capacity
    log_bucket = module.waf_cloudfront.s3_bucket_name
  }
}

output "us_east_1_waf" {
  description = "US East 1 Regional WAF configuration"
  value = {
    id            = module.waf_us_east_1.web_acl_id
    arn           = module.waf_us_east_1.web_acl_arn
    capacity      = module.waf_us_east_1.web_acl_capacity
    log_group     = module.waf_us_east_1.cloudwatch_log_group_name
    cost_estimate = module.waf_us_east_1.cost_estimate_monthly
  }
}

output "us_west_2_waf" {
  description = "US West 2 Regional WAF configuration"
  value = {
    id            = module.waf_us_west_2.web_acl_id
    arn           = module.waf_us_west_2.web_acl_arn
    capacity      = module.waf_us_west_2.web_acl_capacity
    log_group     = module.waf_us_west_2.cloudwatch_log_group_name
    cost_estimate = module.waf_us_west_2.cost_estimate_monthly
  }
}

output "eu_west_1_waf" {
  description = "EU West 1 Regional WAF configuration"
  value = {
    id            = module.waf_eu_west_1.web_acl_id
    arn           = module.waf_eu_west_1.web_acl_arn
    capacity      = module.waf_eu_west_1.web_acl_capacity
    log_group     = module.waf_eu_west_1.cloudwatch_log_group_name
    cost_estimate = module.waf_eu_west_1.cost_estimate_monthly
  }
}

output "total_monthly_cost_estimate" {
  description = "Total estimated monthly cost across all regions"
  value = {
    cloudfront_base   = module.waf_cloudfront.cost_estimate_monthly.estimated_total_base
    us_east_1_base    = module.waf_us_east_1.cost_estimate_monthly.estimated_total_base
    us_west_2_base    = module.waf_us_west_2.cost_estimate_monthly.estimated_total_base
    eu_west_1_base    = module.waf_eu_west_1.cost_estimate_monthly.estimated_total_base
    total_base        = module.waf_cloudfront.cost_estimate_monthly.estimated_total_base + module.waf_us_east_1.cost_estimate_monthly.estimated_total_base + module.waf_us_west_2.cost_estimate_monthly.estimated_total_base + module.waf_eu_west_1.cost_estimate_monthly.estimated_total_base
    note              = "Plus per-request charges based on traffic volume"
  }
}
