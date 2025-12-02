# Security Monitoring Component

This Terraform component implements comprehensive security monitoring for AWS environments using GuardDuty, Security Hub, and Inspector V2.

## Features

- **AWS GuardDuty**: Intelligent threat detection for AWS accounts and workloads
  - S3 protection
  - EKS audit log analysis
  - EC2 malware protection

- **AWS Security Hub**: Centralized security findings aggregation
  - CIS AWS Foundations Benchmark
  - AWS Foundational Security Best Practices
  - PCI-DSS compliance (optional)

- **AWS Inspector V2**: Automated vulnerability management
  - EC2 instance scanning
  - ECR container image scanning
  - Lambda function scanning

- **Alert Management**:
  - SNS topic for security alerts
  - EventBridge rules for HIGH/CRITICAL findings
  - Optional Lambda enrichment for Slack/PagerDuty integration
  - Email notifications

- **CloudWatch Alarms**:
  - Root account usage detection
  - Unauthorized API calls
  - IAM policy changes
  - Security group modifications

## Usage

```hcl
module "security_monitoring" {
  source = "../../components/terraform/security-monitoring"

  region = "us-east-1"

  enable_guardduty    = true
  enable_security_hub = true
  enable_inspector    = true

  security_email_subscriptions = [
    "security-team@example.com"
  ]

  enable_alert_enrichment     = true
  slack_webhook_url           = var.slack_webhook_url
  pagerduty_integration_key   = var.pagerduty_key

  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}
```

## Requirements

- AWS account with appropriate permissions
- CloudTrail enabled for metric filters
- KMS key for encryption (optional)

## Alert Enrichment Lambda

The optional alert enrichment Lambda function:
- Enhances security findings with additional context
- Routes alerts to Slack and PagerDuty
- Provides formatted notifications with severity indicators
- Includes remediation guidance

## Best Practices

1. Enable all protection features in production
2. Configure email notifications for security team
3. Integrate with incident response tools (PagerDuty, Slack)
4. Review findings regularly
5. Set up automated remediation for common issues
6. Enable encryption for SNS topics and logs
7. Retain logs for compliance requirements (90+ days)

## Compliance

This component helps meet compliance requirements for:
- CIS AWS Foundations Benchmark
- AWS Foundational Security Best Practices
- PCI-DSS (when enabled)
- SOC 2
- ISO 27001
- HIPAA (with additional controls)
