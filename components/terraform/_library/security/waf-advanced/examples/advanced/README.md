# Advanced WAF Example

This example demonstrates a comprehensive WAF configuration with bot control, geo-blocking, custom rules, and CloudWatch monitoring.

## Features

- **Full Managed Rule Protection**:
  - OWASP Core Rule Set
  - Known Bad Inputs
  - SQL Database Protection
  - Linux OS Protection
  - IP Reputation List

- **Bot Control**: ML-based bot detection with TARGETED inspection level
- **Rate Limiting**: Strict limit of 1000 requests per 5 minutes
- **Geo-Blocking**: Block high-risk countries (configurable)
- **Custom Rules**:
  - Block /admin paths
  - Block /api/admin paths
  - Block requests with large body (>8KB)
- **CloudWatch Logging**: 90-day retention for compliance
- **CloudWatch Alarms**: Monitoring for blocked and rate-limited requests

## Usage

```bash
# Initialize Terraform
terraform init

# Plan with all features enabled
terraform plan \
  -var="name_prefix=myapp-prod-api" \
  -var="enable_bot_control=true" \
  -var="enable_geo_blocking=true" \
  -var="geo_block_countries=[\"CN\",\"RU\",\"KP\"]" \
  -var="resource_arns=[\"arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/api-alb/xyz789\"]"

# Apply with bot control disabled (cost savings)
terraform apply \
  -var="name_prefix=myapp-prod-api" \
  -var="enable_bot_control=false" \
  -var="enable_geo_blocking=true" \
  -var="resource_arns=[\"arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/api-alb/xyz789\"]"
```

## Cost Estimate

### With Bot Control Enabled

**Monthly Base Cost**: ~$32
- Web ACL: $5
- Managed Rules (5): $5
- Custom Rules (3): $3
- Bot Control: $10
- Rate Limiting: $1
- Geo-Blocking: $1
- Requests (10M at $1.60/M): $16

**Plus Logging**: ~$5-10/month for CloudWatch

**Total**: ~$37-42/month for 10 million requests

### Without Bot Control (Recommended for Cost Savings)

**Monthly Base Cost**: ~$21
- Web ACL: $5
- Managed Rules (5): $5
- Custom Rules (3): $3
- Rate Limiting: $1
- Geo-Blocking: $1
- Requests (10M at $0.60/M): $6

**Plus Logging**: ~$5-10/month for CloudWatch

**Total**: ~$26-31/month for 10 million requests

## What Gets Created

- WAF Web ACL with 8+ rules
- CloudWatch log group (encrypted, 90-day retention)
- WAF logging configuration
- CloudWatch alarms:
  - Blocked requests threshold alert
  - Rate limiting alert
- Resource associations

## Monitoring

### CloudWatch Metrics

The following metrics are available:

- `BlockedRequests` - Total blocked requests
- `AllowedRequests` - Total allowed requests
- `CountedRequests` - Requests in COUNT mode

### CloudWatch Alarms

- **Blocked Requests**: Triggers when >100 requests blocked in 5 minutes
- **Rate Limited**: Triggers when >50 requests rate-limited in 5 minutes

### CloudWatch Logs Insights Queries

```sql
# Top 10 blocked countries
fields @timestamp, httpRequest.country, httpRequest.uri
| filter action = "BLOCK"
| stats count() by httpRequest.country
| sort count desc
| limit 10

# Top 10 blocked IPs
fields @timestamp, httpRequest.clientIp, terminatingRuleId
| filter action = "BLOCK"
| stats count() by httpRequest.clientIp
| sort count desc
| limit 10

# Bot control detections
fields @timestamp, httpRequest.uri, labels
| filter terminatingRuleId like /bot-control/
| limit 100
```

## Security Considerations

1. **Bot Control Cost**: Only enable if bot traffic is a significant problem. Without bot control, the configuration still provides strong protection at ~40% of the cost.

2. **Geo-Blocking**: Carefully consider which countries to block. Blocking too many countries may impact legitimate users. Default blocks CN, RU, KP.

3. **Custom Rules**: The admin path blocking rules protect sensitive endpoints. Adjust the paths based on your application.

4. **Rate Limiting**: 1000 requests per 5 minutes is strict. Increase if you have legitimate high-traffic users.

5. **Anonymous IP Blocking**: Disabled by default as it blocks VPN users. Enable only if VPN traffic is a concern.

## Testing

Before deploying to production:

1. **Test with COUNT Mode**: Change all custom rule actions to "COUNT" to observe without blocking
2. **Monitor Logs**: Review CloudWatch logs for false positives
3. **Adjust Thresholds**: Tune rate limits based on legitimate traffic patterns
4. **Gradual Rollout**: Start with basic rules, add more as needed

## Requirements

- Terraform >= 1.5.0
- AWS Provider >= 5.0.0
- Existing ALB or API Gateway to protect
- CloudWatch Logs permissions
