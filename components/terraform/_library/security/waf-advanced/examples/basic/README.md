# Basic WAF Example

This example demonstrates a basic WAF configuration with OWASP protection suitable for most web applications.

## Features

- OWASP Core Rule Set (protection against Top 10 vulnerabilities)
- Known Bad Inputs blocking
- IP Reputation list
- Rate limiting (2000 requests per 5 minutes per IP)
- S3 logging with 30-day retention

## Usage

```bash
# Initialize Terraform
terraform init

# Review the plan
terraform plan -var="name_prefix=myapp-prod" \
               -var="alb_arns=[\"arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/my-alb/abc123\"]"

# Apply the configuration
terraform apply -var="name_prefix=myapp-prod" \
                -var="alb_arns=[\"arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/my-alb/abc123\"]"
```

## Cost Estimate

**Monthly Base Cost**: ~$14
- Web ACL: $5
- Managed Rules (3): $3
- Rate Limiting Rule: $1
- Requests (10M): $6

**Plus Logging**: ~$2-5/month for S3 storage

**Total**: ~$16-19/month for 10 million requests

## What Gets Created

- WAF Web ACL with 4 rules
- S3 bucket for logs (encrypted, versioned)
- WAF logging configuration
- Resource associations

## Requirements

- Terraform >= 1.5.0
- AWS Provider >= 5.0.0
- Existing ALB to protect (optional for testing)
