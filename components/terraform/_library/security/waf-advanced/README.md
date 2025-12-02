# Advanced WAF Module

Production-grade AWS WAF with OWASP Top 10, bot control, and rate limiting.

## Overview

This module creates a comprehensive AWS WAFv2 Web Application Firewall with enterprise-grade protection features including:

- **OWASP Top 10 Protection**: Core Rule Set defending against common web vulnerabilities
- **Bot Control**: Intelligent bot detection and mitigation
- **Rate Limiting**: Prevent abuse and DDoS attacks
- **IP Reputation**: Block known malicious IP addresses
- **Geo-Blocking**: Control access by geographic location
- **Custom Rules**: Build application-specific protection rules
- **Comprehensive Logging**: S3, CloudWatch, or Kinesis Firehose integration
- **Cost-Optimized Rule Ordering**: Rules ordered by cost for maximum efficiency

## Features

- Pre-configured AWS Managed Rule Groups (OWASP, SQL injection, XSS, etc.)
- Bot Control with COMMON or TARGETED inspection levels
- Rate limiting per IP address with configurable thresholds
- IP reputation lists (malicious IPs, anonymous proxies, VPNs)
- Geographic blocking or allow-listing
- Custom rule builder for application-specific needs
- Automatic log rotation and retention
- CloudWatch metrics for all rules
- Support for CloudFront and Regional (ALB/API Gateway) deployments
- Redacted sensitive headers in logs (Authorization, Cookie)

## Usage

### Basic Example

```hcl
module "waf" {
  source = "../../_library/security/waf-advanced"

  name_prefix = "acme-prod-web"
  scope       = "REGIONAL"

  # Enable OWASP protection
  enable_core_rule_set      = true
  enable_known_bad_inputs   = true
  enable_ip_reputation      = true

  # Basic rate limiting
  enable_rate_limiting = true
  rate_limit_per_ip    = 2000
  rate_limit_window    = 300

  # Enable logging to S3
  enable_logging        = true
  log_destination_type  = "s3"
  log_retention_days    = 30

  # Associate with Application Load Balancer
  resource_arns = [
    "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/my-alb/abc123"
  ]

  tags = {
    Environment = "production"
    Application = "web"
  }
}
```

### Advanced Example with Bot Control

```hcl
module "waf_advanced" {
  source = "../../_library/security/waf-advanced"

  name_prefix = "acme-prod-api"
  scope       = "REGIONAL"

  # Full managed rule protection
  enable_core_rule_set             = true
  enable_known_bad_inputs          = true
  enable_sql_database_protection   = true
  enable_ip_reputation             = true
  enable_anonymous_ip_list         = false  # May block legitimate VPN users

  # Bot control with targeted detection
  enable_bot_control = true
  bot_control_level  = "TARGETED"

  # Strict rate limiting
  enable_rate_limiting = true
  rate_limit_per_ip    = 1000
  rate_limit_window    = 300

  # Geo-blocking for specific countries
  enable_geo_blocking  = true
  geo_block_countries  = ["CN", "RU", "KP"]

  # Custom rule to block admin paths
  custom_rules = [
    {
      name     = "block-admin-path"
      priority = 100
      action   = "BLOCK"
      statement = {
        byte_match_statement = {
          positional_constraint = "STARTS_WITH"
          search_string        = "/admin"
          field_to_match = {
            uri_path = true
            body     = false
          }
          text_transformation = ["LOWERCASE"]
        }
        size_constraint_statement = null
      }
    }
  ]

  # CloudWatch logging
  enable_logging        = true
  log_destination_type  = "cloudwatch"
  log_retention_days    = 90

  resource_arns = [
    "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/api-alb/xyz789"
  ]

  tags = {
    Environment = "production"
    Application = "api"
    Compliance  = "pci-dss"
  }
}
```

### CloudFront Example

```hcl
module "waf_cloudfront" {
  source = "../../_library/security/waf-advanced"

  # CloudFront WAF must be created in us-east-1
  providers = {
    aws = aws.us_east_1
  }

  name_prefix = "acme-prod-cdn"
  scope       = "CLOUDFRONT"

  enable_core_rule_set    = true
  enable_known_bad_inputs = true
  enable_ip_reputation    = true
  enable_rate_limiting    = true

  resource_arns = [
    "arn:aws:cloudfront::123456789012:distribution/E1ABCDEFGHIJKL"
  ]

  tags = {
    Environment = "production"
    Service     = "cdn"
  }
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5.0 |
| aws | >= 5.0.0, < 6.0.0 |

## Providers

| Name | Version |
|------|---------|
| aws | >= 5.0.0, < 6.0.0 |

## Resources

| Name | Type |
|------|------|
| aws_wafv2_web_acl.main | resource |
| aws_wafv2_web_acl_logging_configuration.main | resource |
| aws_wafv2_web_acl_association.main | resource |
| aws_s3_bucket.waf_logs | resource |
| aws_s3_bucket_public_access_block.waf_logs | resource |
| aws_s3_bucket_versioning.waf_logs | resource |
| aws_s3_bucket_server_side_encryption_configuration.waf_logs | resource |
| aws_s3_bucket_lifecycle_configuration.waf_logs | resource |
| aws_cloudwatch_log_group.waf_logs | resource |
| aws_caller_identity.current | data source |
| aws_region.current | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| name_prefix | Prefix for resource names | `string` | n/a | yes |
| scope | WAF scope (CLOUDFRONT or REGIONAL) | `string` | `"REGIONAL"` | no |
| enable_core_rule_set | Enable OWASP Core Rule Set | `bool` | `true` | no |
| enable_known_bad_inputs | Enable Known Bad Inputs rule set | `bool` | `true` | no |
| enable_sql_database_protection | Enable SQL injection protection | `bool` | `false` | no |
| enable_linux_os_protection | Enable Linux OS protection | `bool` | `false` | no |
| enable_unix_os_protection | Enable Unix OS protection | `bool` | `false` | no |
| enable_windows_os_protection | Enable Windows OS protection | `bool` | `false` | no |
| enable_php_application_protection | Enable PHP application protection | `bool` | `false` | no |
| enable_wordpress_protection | Enable WordPress protection | `bool` | `false` | no |
| enable_bot_control | Enable Bot Control | `bool` | `false` | no |
| bot_control_level | Bot Control level (COMMON or TARGETED) | `string` | `"COMMON"` | no |
| enable_rate_limiting | Enable rate limiting | `bool` | `true` | no |
| rate_limit_per_ip | Max requests per IP in time window | `number` | `2000` | no |
| rate_limit_window | Rate limit time window in seconds | `number` | `300` | no |
| enable_ip_reputation | Enable IP reputation list | `bool` | `true` | no |
| enable_anonymous_ip_list | Enable anonymous IP list | `bool` | `false` | no |
| enable_geo_blocking | Enable geographic blocking | `bool` | `false` | no |
| geo_block_countries | Countries to block (ISO 3166-1 alpha-2) | `list(string)` | `[]` | no |
| geo_allow_countries | Countries to allow (blocks all others) | `list(string)` | `[]` | no |
| custom_rules | List of custom WAF rules | `list(object)` | `[]` | no |
| enable_logging | Enable WAF logging | `bool` | `true` | no |
| log_destination_type | Log destination (s3, cloudwatch, kinesis) | `string` | `"s3"` | no |
| log_destination_arn | ARN of log destination | `string` | `""` | no |
| log_retention_days | Log retention period in days | `number` | `30` | no |
| default_action | Default action (ALLOW or BLOCK) | `string` | `"ALLOW"` | no |
| resource_arns | Resources to associate with WAF | `list(string)` | `[]` | no |
| tags | Additional tags | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| web_acl_id | WAF Web ACL ID |
| web_acl_arn | WAF Web ACL ARN |
| web_acl_name | WAF Web ACL name |
| web_acl_capacity | WAF capacity units consumed |
| log_destination_arn | Log destination ARN |
| s3_bucket_name | S3 bucket name for logs |
| s3_bucket_arn | S3 bucket ARN for logs |
| cloudwatch_log_group_name | CloudWatch log group name |
| cloudwatch_log_group_arn | CloudWatch log group ARN |
| enabled_rules_summary | Summary of enabled rules |
| cost_estimate_monthly | Estimated monthly cost |
| associated_resource_arns | Associated resource ARNs |
| cloudwatch_metrics | CloudWatch metrics configuration |

## Cost Estimation

### Base Costs (Monthly)

- **Web ACL**: $5.00/month
- **Managed Rules**: $1.00/month per rule
- **Custom Rules**: $1.00/month per rule
- **Bot Control**: $10.00/month base + $1.00 per 1M requests

### Request-Based Costs

- **Standard Rules**: $0.60 per 1 million requests
- **Bot Control**: $1.00 per 1 million requests (additional)

### Example Configurations

**Basic Protection** (Core Rule Set + Rate Limiting + IP Reputation):
- Base: $5 + $3 (rules) = $8/month
- Requests: 10M requests × $0.60 = $6/month
- **Total: ~$14/month**

**Advanced Protection** (with Bot Control):
- Base: $5 + $8 (rules) + $10 (bot control) = $23/month
- Requests: 10M requests × $1.60 = $16/month
- **Total: ~$39/month**

**Enterprise Protection** (all features):
- Base: $5 + $15 (rules) + $10 (bot control) + $2 (custom rules) = $32/month
- Requests: 50M requests × $1.60 = $80/month
- **Total: ~$112/month**

### Logging Costs

- **S3**: $0.023/GB/month + $0.005 per 1000 PUT requests
- **CloudWatch Logs**: $0.50/GB ingested + $0.03/GB/month storage

**Estimate**: 1-2GB logs per million requests = $2-5/month for moderate traffic

## Architecture

### Rule Evaluation Order

Rules are evaluated in priority order (lowest first) for cost optimization:

1. **Rate Limiting** (Priority 10) - Cheapest, blocks excessive requests early
2. **Geo-Blocking** (Priority 20) - Geographic filtering
3. **IP Reputation** (Priority 30) - Known bad actors
4. **Anonymous IP** (Priority 40) - VPNs, proxies, Tor
5. **Known Bad Inputs** (Priority 50) - Generic bad patterns
6. **Core Rule Set** (Priority 60) - OWASP Top 10
7. **SQL Database** (Priority 70) - Enhanced SQLi protection
8. **OS Protection** (Priority 80-100) - OS-specific exploits
9. **Application Protection** (Priority 110-120) - PHP, WordPress
10. **Bot Control** (Priority 130) - Most expensive, evaluated last
11. **Custom Rules** (Priority 100+) - User-defined rules

### Request Flow

```
Client Request
      ↓
[Rate Limiting] → Block if rate exceeded
      ↓
[Geo-Blocking] → Block/Allow by country
      ↓
[IP Reputation] → Block known bad IPs
      ↓
[Managed Rules] → Check OWASP, SQLi, XSS, etc.
      ↓
[Bot Control] → Analyze bot behavior
      ↓
[Custom Rules] → Application-specific rules
      ↓
[Default Action] → ALLOW or BLOCK
      ↓
Backend Resource
```

## Security Considerations

### OWASP Top 10 Coverage

This module provides protection against:

1. **Injection** - SQL injection, XSS, command injection
2. **Broken Authentication** - Rate limiting prevents brute force
3. **Sensitive Data Exposure** - Log redaction for sensitive headers
4. **XML External Entities (XXE)** - Core Rule Set protection
5. **Broken Access Control** - Custom rules for path restrictions
6. **Security Misconfiguration** - Secure defaults
7. **Cross-Site Scripting (XSS)** - Core Rule Set protection
8. **Insecure Deserialization** - Known Bad Inputs protection
9. **Using Components with Known Vulnerabilities** - Application-specific rule sets
10. **Insufficient Logging & Monitoring** - Comprehensive logging enabled

### Best Practices

1. **Start with Basic Protection**: Enable Core Rule Set and Known Bad Inputs first
2. **Test Before Enforcing**: Use COUNT action to test rules before blocking
3. **Monitor Metrics**: Set up CloudWatch alarms for blocked requests
4. **Regular Updates**: AWS updates managed rules automatically
5. **Log Analysis**: Review logs regularly for false positives
6. **Rate Limit Tuning**: Adjust based on legitimate traffic patterns
7. **Geo-Blocking Caution**: Only block countries if you have no users there
8. **Bot Control Cost**: Only enable if bots are a significant problem

### Compliance

This module helps achieve compliance with:

- **PCI DSS 6.6**: WAF protecting against known attacks
- **HIPAA**: Encryption, logging, and access controls
- **SOC 2**: Security monitoring and incident response
- **GDPR**: Data protection and privacy controls

## Performance

- **Deployment Time**: ~15 minutes
- **Resource Count**: 8-25 resources (depending on configuration)
- **State Size**: ~120 KB
- **Request Latency**: < 1ms added latency per request

## Troubleshooting

### Issue: Too Many False Positives

**Symptoms**: Legitimate requests being blocked

**Solutions**:
1. Review CloudWatch metrics to identify which rule is blocking
2. Use COUNT mode temporarily to observe without blocking
3. Add exclusions to managed rule groups
4. Adjust rate limiting thresholds
5. Review custom rules for overly broad patterns

### Issue: Bot Control Too Expensive

**Symptoms**: High AWS WAF bills

**Solutions**:
1. Use COMMON instead of TARGETED inspection level
2. Only enable bot control on critical endpoints
3. Use rate limiting instead for basic bot protection
4. Consider CloudFront bot protection as alternative

### Issue: Logs Not Appearing

**Symptoms**: WAF logs missing

**Solutions**:
1. Verify log destination ARN is correct
2. Check S3 bucket name starts with "aws-waf-logs-"
3. Ensure proper IAM permissions on log destination
4. Wait 5-10 minutes for first logs to appear
5. Check Web ACL is associated with resources

### Issue: CloudFront Association Fails

**Symptoms**: Cannot associate WAF with CloudFront

**Solutions**:
1. Ensure WAF is created in us-east-1 region
2. Use scope = "CLOUDFRONT"
3. Verify CloudFront distribution exists
4. Check CloudFront distribution is not already associated with another WAF

## Migration Guide

### From Manually Managed WAF

1. Export existing WAF configuration
2. Map rules to module variables
3. Import existing Web ACL: `terraform import module.waf.aws_wafv2_web_acl.main <web-acl-id>`
4. Run `terraform plan` to verify no changes
5. Apply any configuration updates

### From WAFv1 (Classic)

WAFv2 is significantly different from WAFv1. Migration requires:

1. Create new WAFv2 Web ACL with this module
2. Test parallel to existing WAFv1
3. Switch traffic to WAFv2
4. Decommission WAFv1

## Examples

- [Basic](./examples/basic) - Simple WAF with OWASP protection
- [Advanced](./examples/advanced) - Full-featured WAF with bot control
- [Multi-Region](./examples/multi-region) - WAF across multiple regions

## Contributing

See [CONTRIBUTING.md](../../CONTRIBUTING.md)

## License

See [LICENSE](./LICENSE)

## Maintainers

- Security Engineering Team (@security-team)
- Primary: security-team@example.com
- Backup: platform-team@example.com

## Changelog

See [CHANGELOG.md](./CHANGELOG.md)
