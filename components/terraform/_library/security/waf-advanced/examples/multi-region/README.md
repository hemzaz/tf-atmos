# Multi-Region WAF Example

This example demonstrates deploying WAF across multiple AWS regions and for CloudFront distributions.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                       CloudFront (Global)                    │
│                    WAF (us-east-1 - required)               │
│                    Scope: CLOUDFRONT                         │
└─────────────────────────────────────────────────────────────┘
                              │
                    ┌─────────┴─────────┐
                    │                   │
          ┌─────────▼────────┐  ┌──────▼──────────┐
          │   US Regions     │  │   EU Region     │
          │                  │  │                 │
          │  ┌────────────┐  │  │  ┌───────────┐ │
          │  │ US East 1  │  │  │  │ EU West 1 │ │
          │  │ WAF        │  │  │  │ WAF       │ │
          │  │ (REGIONAL) │  │  │  │ (REGIONAL)│ │
          │  └────────────┘  │  │  └───────────┘ │
          │                  │  │                 │
          │  ┌────────────┐  │  │  Geo-blocking: │
          │  │ US West 2  │  │  │  EU allow-list │
          │  │ WAF        │  │  │                 │
          │  │ (REGIONAL) │  │  │                 │
          │  └────────────┘  │  │                 │
          └──────────────────┘  └─────────────────┘
```

## Features

### CloudFront WAF (Global)
- Deployed in us-east-1 (AWS requirement)
- Protects CloudFront distributions
- Higher rate limits for CDN traffic
- S3 logging

### Regional WAFs
- **US East 1**: Primary region with CloudWatch logging
- **US West 2**: West coast region with CloudWatch logging
- **EU West 1**: EU region with GDPR compliance features:
  - Geo-blocking with EU allow-list
  - 90-day log retention
  - Enhanced privacy controls

## Usage

### Configure Providers

Ensure you have AWS credentials configured for all regions:

```bash
export AWS_PROFILE=default
# Or configure in ~/.aws/credentials
```

### Deploy All Regions

```bash
# Initialize with multiple providers
terraform init

# Plan deployment
terraform plan \
  -var="name_prefix=myapp-prod" \
  -var="cloudfront_distribution_arns=[\"arn:aws:cloudfront::123456789012:distribution/E1EXAMPLE\"]" \
  -var="us_east_1_resource_arns=[\"arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/api-use1/abc123\"]" \
  -var="us_west_2_resource_arns=[\"arn:aws:elasticloadbalancing:us-west-2:123456789012:loadbalancer/app/api-usw2/def456\"]" \
  -var="eu_west_1_resource_arns=[\"arn:aws:elasticloadbalancing:eu-west-1:123456789012:loadbalancer/app/api-euw1/ghi789\"]"

# Apply configuration
terraform apply
```

### Deploy Specific Regions

You can selectively deploy to specific regions using targets:

```bash
# Deploy only CloudFront WAF
terraform apply -target=module.waf_cloudfront

# Deploy only EU WAF
terraform apply -target=module.waf_eu_west_1
```

## Cost Estimate

**Total Monthly Base Cost**: ~$32 (4 WAFs × $8 average)

### Per Region Breakdown:
- **CloudFront**: $8/month base + $0.60 per 1M requests
- **US East 1**: $8/month base + $0.60 per 1M requests
- **US West 2**: $8/month base + $0.60 per 1M requests
- **EU West 1**: $8/month base + $0.60 per 1M requests

### Example Traffic Costs:
**100M requests/month total** (25M per WAF average):
- Base: $32
- Requests: 100M × $0.60 = $60
- Logging: ~$15-20
- **Total: ~$107-112/month**

## What Gets Created

### Per Region:
- WAF Web ACL with 4 rules
- CloudWatch log group (or S3 bucket for CloudFront)
- WAF logging configuration
- Resource associations

### Total Resources:
- 4 WAF Web ACLs
- 3 CloudWatch log groups
- 1 S3 bucket (CloudFront logs)
- 4 logging configurations
- Resource associations per region

## Regional Differences

### CloudFront (us-east-1)
- **Scope**: CLOUDFRONT
- **Rate Limit**: 5000 req/5min (higher for CDN)
- **Logging**: S3 bucket
- **Purpose**: Global edge protection

### US Regions (us-east-1, us-west-2)
- **Scope**: REGIONAL
- **Rate Limit**: 2000 req/5min
- **Logging**: CloudWatch Logs (60-day retention)
- **Purpose**: Regional ALB/API Gateway protection

### EU Region (eu-west-1)
- **Scope**: REGIONAL
- **Rate Limit**: 2000 req/5min
- **Logging**: CloudWatch Logs (90-day retention for GDPR)
- **Geo-Blocking**: EU allow-list (blocks non-EU/US/CA traffic)
- **Purpose**: GDPR-compliant regional protection

## GDPR Compliance (EU Region)

The EU WAF includes enhanced privacy features:

1. **Extended Log Retention**: 90 days for compliance audits
2. **Geo-Blocking**: Optional allow-list for EU countries + partners
3. **Sensitive Data Redaction**: Authorization and Cookie headers
4. **Encryption**: CloudWatch logs encrypted at rest
5. **Access Controls**: IAM policies for log access

## Monitoring Across Regions

### CloudWatch Insights Query (Cross-Region)

You cannot directly query across regions, but you can aggregate:

```bash
# Query US East 1
aws logs tail "/aws/wafv2/example-multiregion-use1" --follow --region us-east-1

# Query US West 2
aws logs tail "/aws/wafv2/example-multiregion-usw2" --follow --region us-west-2

# Query EU West 1
aws logs tail "/aws/wafv2/example-multiregion-euw1" --follow --region eu-west-1
```

### CloudWatch Dashboard

Create a cross-region dashboard:

```hcl
resource "aws_cloudwatch_dashboard" "waf_global" {
  dashboard_name = "waf-global-overview"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/WAFV2", "BlockedRequests", { region = "us-east-1" }],
            ["...", { region = "us-west-2" }],
            ["...", { region = "eu-west-1" }]
          ]
          period = 300
          stat   = "Sum"
          region = "us-east-1"
          title  = "Blocked Requests by Region"
        }
      }
    ]
  })
}
```

## High Availability Strategy

### Failover Scenarios

1. **Regional Failure**: Each region's WAF operates independently
2. **CloudFront Failure**: Regional WAFs continue protecting direct access
3. **WAF Service Disruption**: Requests pass through (fail-open)

### Best Practices

1. **Consistent Rules**: Use same rule configuration across regions
2. **Centralized Logging**: Aggregate logs to central S3 bucket or SIEM
3. **Automated Deployment**: Use CI/CD for consistent deployments
4. **Regular Testing**: Test WAF in each region periodically

## Migration Strategy

### Adding New Region

```hcl
module "waf_ap_southeast_1" {
  source = "../../"

  providers = {
    aws = aws.ap_southeast_1
  }

  name_prefix = "${var.name_prefix}-apse1"
  scope       = "REGIONAL"

  # Copy configuration from existing regions
  enable_core_rule_set    = true
  enable_known_bad_inputs = true
  enable_ip_reputation    = true
  enable_rate_limiting    = true

  resource_arns = var.ap_southeast_1_resource_arns

  tags = merge(var.tags, {
    Region = "ap-southeast-1"
  })
}
```

### Removing Region

```bash
# Remove from state
terraform state rm module.waf_us_west_2

# Remove from configuration
# Comment out or delete module block

# Apply to destroy resources
terraform apply
```

## Requirements

- Terraform >= 1.5.0
- AWS Provider >= 5.0.0
- AWS credentials with permissions in all target regions
- Existing resources (ALB, CloudFront) to protect

## Testing

1. **Test CloudFront WAF**: Access CloudFront distribution and verify WAF metrics
2. **Test Regional WAFs**: Access ALBs in each region
3. **Verify Geo-Blocking**: Test from blocked countries (use VPN)
4. **Check Logs**: Verify logs appear in all destinations
5. **Cost Monitoring**: Set up AWS Cost Explorer alerts
