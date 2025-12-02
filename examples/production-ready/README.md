# Production-Ready Example

This example demonstrates a complete production-grade infrastructure deployment with high availability, security, and monitoring.

## Overview

The production-ready deployment includes:

### Networking
- Multi-VPC architecture (main + services)
- Multi-AZ deployment (3 AZs)
- One NAT Gateway per AZ
- VPC Flow Logs enabled
- VPC peering between VPCs

### Compute
- EKS cluster with multiple node groups
- Auto-scaling enabled
- Private endpoints only
- Secrets encryption with KMS

### Data
- RDS PostgreSQL (Multi-AZ)
- ElastiCache Redis (clustered)
- Automated backups
- Point-in-time recovery

### Security
- GuardDuty enabled
- Security Hub enabled
- KMS encryption everywhere
- Secrets rotation enabled
- WAF for API Gateway

### Monitoring
- CloudWatch dashboards
- Comprehensive alarms
- PagerDuty integration
- Certificate monitoring

## Prerequisites

- AWS CLI configured with production credentials
- Terraform 1.11+
- Atmos 1.163.0+
- Domain name in Route53
- ACM certificate

## Deployment Steps

### 1. Prepare Configuration

```bash
# Copy example configuration
cp -r examples/production-ready/stacks/* stacks/orgs/

# Update with your values
vim stacks/orgs/acme/prod/eu-west-2/production.yaml
```

### 2. Configure Environment

```bash
# Set production environment variables
export AWS_PROFILE=prod
export AWS_REGION=eu-west-2
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Verify credentials
aws sts get-caller-identity
```

### 3. Bootstrap Backend

```bash
# Create backend infrastructure
atmos workflow full -f bootstrap.yaml \
  tenant=acme account=prod environment=production \
  auto_approve=true
```

### 4. Security Audit (Pre-Deployment)

```bash
# Run security audit
atmos workflow security-audit -f security-hardening.yaml \
  tenant=acme account=prod environment=production
```

### 5. Deploy Infrastructure

```bash
# Generate deployment plan (review before applying)
atmos workflow deploy -f deploy-full-stack.yaml \
  tenant=acme account=prod environment=production

# Review plans carefully, then apply
atmos workflow deploy -f deploy-full-stack.yaml \
  tenant=acme account=prod environment=production \
  auto_approve=true
```

### 6. Post-Deployment Verification

```bash
# Check DR readiness
atmos workflow dr-status -f disaster-recovery.yaml \
  tenant=acme account=prod environment=production

# Run security audit again
atmos workflow security-audit -f security-hardening.yaml \
  tenant=acme account=prod environment=production

# Verify all alarms are configured
aws cloudwatch describe-alarms \
  --alarm-name-prefix "acme-production"
```

## Architecture

```
+------------------------------------------------------------------+
|                        AWS Account (Production)                    |
+------------------------------------------------------------------+
|                                                                    |
|  +------------------------+    +------------------------+          |
|  |      Main VPC         |    |    Services VPC        |          |
|  |   10.20.0.0/16        |<-->|   10.21.0.0/16        |          |
|  +------------------------+    +------------------------+          |
|  |                        |    |                        |          |
|  | +------------------+   |    | +------------------+   |          |
|  | | Public Subnets   |   |    | | Public Subnets   |   |          |
|  | | (3 AZs)          |   |    | | (3 AZs)          |   |          |
|  | | - ALB            |   |    | | - NAT GW         |   |          |
|  | | - NAT GW         |   |    | +------------------+   |          |
|  | +------------------+   |    |                        |          |
|  |                        |    | +------------------+   |          |
|  | +------------------+   |    | | Private Subnets  |   |          |
|  | | Private Subnets  |   |    | | (3 AZs)          |   |          |
|  | | (3 AZs)          |   |    | | - Data EKS      |   |          |
|  | | - Main EKS       |   |    | | - Lambda        |   |          |
|  | | - EC2            |   |    | +------------------+   |          |
|  | +------------------+   |    |                        |          |
|  |                        |    | +------------------+   |          |
|  | +------------------+   |    | | Database Subnets |   |          |
|  | | Database Subnets |   |    | | (3 AZs)          |   |          |
|  | | (3 AZs)          |   |    | | - Data RDS      |   |          |
|  | | - Main RDS       |   |    | +------------------+   |          |
|  | | - ElastiCache    |   |    |                        |          |
|  | +------------------+   |    +------------------------+          |
|  +------------------------+                                        |
|                                                                    |
|  +------------------------+    +------------------------+          |
|  |    Security Services   |    |   Monitoring Services  |          |
|  +------------------------+    +------------------------+          |
|  | - GuardDuty           |    | - CloudWatch           |          |
|  | - Security Hub        |    | - SNS Topics           |          |
|  | - KMS Keys            |    | - Dashboards           |          |
|  | - Secrets Manager     |    | - Alarms               |          |
|  +------------------------+    +------------------------+          |
|                                                                    |
+------------------------------------------------------------------+
```

## Configuration Files

```
stacks/orgs/acme/prod/eu-west-2/production/
├── components/
│   ├── globals.yaml       # Environment-wide settings
│   ├── networking.yaml    # VPC and network configuration
│   ├── security.yaml      # IAM, secrets, certificates
│   ├── compute.yaml       # EKS, EC2, external-secrets
│   └── services.yaml      # API Gateway, RDS, monitoring
└── production.yaml        # Main stack file
```

## Estimated Cost

| Resource | Monthly Cost (USD) |
|----------|-------------------|
| VPC (NAT Gateways x 6) | ~$192 |
| EKS Control Plane x 2 | ~$146 |
| EKS Workers (m5.xlarge x 6) | ~$830 |
| EKS Workers (r5.2xlarge x 4) | ~$1,460 |
| RDS (r5.xlarge Multi-AZ) | ~$580 |
| RDS (r5.2xlarge Multi-AZ) | ~$1,160 |
| ElastiCache (r5.large x 3) | ~$370 |
| S3 (state, logs, backups) | ~$50 |
| CloudWatch | ~$100 |
| Secrets Manager | ~$20 |
| GuardDuty | ~$50 |
| **Total** | **~$5,000** |

*Costs are estimates and vary by usage.*

## Security Checklist

- [x] Multi-AZ deployment
- [x] Private subnets for compute
- [x] Encrypted storage (KMS)
- [x] Secrets in Secrets Manager
- [x] Secrets rotation enabled
- [x] GuardDuty enabled
- [x] Security Hub enabled
- [x] VPC Flow Logs enabled
- [x] IMDSv2 required
- [x] Private EKS endpoints
- [x] WAF on API Gateway
- [x] Deletion protection enabled

## Operational Runbooks

- [Scaling EKS](../../docs/runbooks/eks-scaling.md)
- [RDS Failover](../../docs/runbooks/rds-failover.md)
- [Incident Response](../../docs/runbooks/incident-response.md)
- [Disaster Recovery](../../docs/runbooks/disaster-recovery.md)

## Support

For production issues:
- Critical: Contact on-call via PagerDuty
- Non-critical: File issue in repository
