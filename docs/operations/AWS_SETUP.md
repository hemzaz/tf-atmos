# AWS Backend Setup and Configuration Guide

This guide provides comprehensive instructions for setting up AWS backend infrastructure for Terraform state management in the Terraform/Atmos project.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [AWS Account Requirements](#aws-account-requirements)
- [Quick Start](#quick-start)
- [Advanced Configuration](#advanced-configuration)
- [Cross-Account Setup](#cross-account-setup)
- [Security Best Practices](#security-best-practices)
- [Troubleshooting](#troubleshooting)
- [Multi-Environment Strategy](#multi-environment-strategy)
- [Monitoring and Maintenance](#monitoring-and-maintenance)

## Overview

The AWS backend setup creates and configures:
- **S3 buckets** for Terraform state storage with versioning, encryption, and lifecycle policies
- **DynamoDB tables** for state locking with point-in-time recovery
- **KMS keys** for encryption at rest
- **IAM policies** and cross-account roles (when needed)
- **Monitoring and logging** infrastructure

## Prerequisites

### Required Tools

```bash
# AWS CLI v2 (recommended)
aws --version

# Terraform (for validation)
terraform version

# Atmos CLI
atmos version

# jq (for JSON processing)
jq --version

# Optional: Gaia CLI
gaia version
```

### AWS Credentials

Configure AWS credentials using one of these methods:

#### Option 1: AWS CLI Configuration
```bash
aws configure
```

#### Option 2: Environment Variables
```bash
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_REGION="us-east-1"
```

#### Option 3: AWS Profiles
```bash
export AWS_PROFILE="your-profile-name"
```

#### Option 4: IAM Roles (for EC2/Container environments)
Use instance profiles or task roles - no additional configuration needed.

## AWS Account Requirements

### Required IAM Permissions

The AWS user/role needs the following permissions to create backend infrastructure:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:CreateBucket",
                "s3:DeleteBucket",
                "s3:GetBucketVersioning",
                "s3:GetBucketEncryption",
                "s3:GetBucketLocation",
                "s3:GetBucketLogging",
                "s3:ListBucket",
                "s3:PutBucketVersioning",
                "s3:PutBucketEncryption",
                "s3:PutBucketLogging",
                "s3:PutBucketPolicy",
                "s3:PutBucketPublicAccessBlock",
                "s3:PutBucketTagging",
                "s3:PutLifecycleConfiguration",
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject"
            ],
            "Resource": [
                "arn:aws:s3:::*-terraform-state",
                "arn:aws:s3:::*-terraform-state/*",
                "arn:aws:s3:::*-terraform-state-*",
                "arn:aws:s3:::*-terraform-state-*/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "dynamodb:CreateTable",
                "dynamodb:DeleteTable",
                "dynamodb:DescribeTable",
                "dynamodb:DescribeContinuousBackups",
                "dynamodb:UpdateContinuousBackups",
                "dynamodb:ListTables",
                "dynamodb:TagResource",
                "dynamodb:UntagResource",
                "dynamodb:GetItem",
                "dynamodb:PutItem",
                "dynamodb:DeleteItem"
            ],
            "Resource": [
                "arn:aws:dynamodb:*:*:table/*-terraform-locks"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "kms:CreateKey",
                "kms:CreateAlias",
                "kms:DescribeKey",
                "kms:GetKeyPolicy",
                "kms:PutKeyPolicy",
                "kms:ListKeys",
                "kms:ListAliases",
                "kms:TagResource",
                "kms:Encrypt",
                "kms:Decrypt",
                "kms:GenerateDataKey"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "sts:GetCallerIdentity",
                "sts:AssumeRole"
            ],
            "Resource": "*"
        }
    ]
}
```

### Account Limits and Quotas

Ensure your AWS account has sufficient quotas:

- **S3**: No specific limits for bucket creation
- **DynamoDB**: Default limit of 2,500 tables per region
- **KMS**: Default limit of 100,000 keys per account per region

## Quick Start

### Method 1: Using the AWS Setup Script (Recommended)

```bash
# Basic setup for development environment
./scripts/aws-setup.sh \
  --tenant fnx \
  --account dev \
  --environment testenv-01

# Production setup with custom region
./scripts/aws-setup.sh \
  --tenant fnx \
  --account prod \
  --environment production \
  --region us-west-2

# Dry run to see what would be created
./scripts/aws-setup.sh \
  --tenant fnx \
  --account dev \
  --environment testenv-01 \
  --dry-run
```

### Method 2: Using Atmos Workflow

```bash
# Bootstrap backend infrastructure
atmos workflow bootstrap-backend \
  tenant=fnx \
  account=dev \
  environment=testenv-01

# With custom region and cross-account role
atmos workflow bootstrap-backend \
  tenant=fnx \
  account=prod \
  environment=production \
  region=us-west-2 \
  assume_role=arn:aws:iam::123456789012:role/TerraformRole
```

### Method 3: Using Makefile

```bash
# Setup AWS backend with default configuration
make setup-aws-backend TENANT=fnx ACCOUNT=dev ENVIRONMENT=testenv-01

# Validate existing backend setup
make validate-aws-setup TENANT=fnx ACCOUNT=dev ENVIRONMENT=testenv-01

# Bootstrap complete environment
make bootstrap-environment TENANT=fnx ACCOUNT=dev ENVIRONMENT=testenv-01
```

## Advanced Configuration

### Custom KMS Key

```bash
# Use existing KMS key
./scripts/aws-setup.sh \
  --tenant fnx \
  --account prod \
  --environment production \
  --kms-key-id arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012

# Or use alias
./scripts/aws-setup.sh \
  --tenant fnx \
  --account prod \
  --environment production \
  --kms-key-id alias/terraform-state-key
```

### Custom Naming Patterns

```bash
# Custom bucket and table suffixes
./scripts/aws-setup.sh \
  --tenant fnx \
  --account dev \
  --environment testenv-01 \
  --bucket-suffix "tf-state" \
  --dynamodb-suffix "tf-locks"
```

### Automated Setup (CI/CD)

```bash
# Fully automated setup for CI/CD pipelines
./scripts/aws-setup.sh \
  --tenant fnx \
  --account prod \
  --environment production \
  --force \
  --region us-west-2
```

## Cross-Account Setup

### Scenario: Central Backend Account

When using a central AWS account for backend infrastructure:

#### 1. Create Cross-Account Role in Backend Account

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "AWS": [
                    "arn:aws:iam::111111111111:root",
                    "arn:aws:iam::222222222222:root"
                ]
            },
            "Action": "sts:AssumeRole",
            "Condition": {
                "StringEquals": {
                    "sts:ExternalId": "unique-external-id"
                }
            }
        }
    ]
}
```

#### 2. Setup Backend with Cross-Account Role

```bash
# Setup backend in central account
./scripts/aws-setup.sh \
  --tenant fnx \
  --account prod \
  --environment production \
  --assume-role arn:aws:iam::333333333333:role/TerraformBackendRole \
  --region us-east-1
```

#### 3. Configure Terraform Backend

The generated configuration will include the role assumption:

```hcl
terraform {
  backend "s3" {
    bucket         = "fnx-prod-production-terraform-state"
    key            = "terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "fnx-prod-production-terraform-locks"
    role_arn       = "arn:aws:iam::333333333333:role/TerraformBackendRole"
    encrypt        = true
  }
}
```

## Security Best Practices

### 1. Bucket Security Configuration

All S3 buckets are configured with:

- **Versioning enabled** for state file recovery
- **Server-side encryption** with KMS or AES-256
- **Public access blocked** at bucket level
- **HTTPS-only access policy**
- **Access logging enabled** (optional)
- **Lifecycle policies** for cost optimization

### 2. DynamoDB Security

DynamoDB tables include:

- **Point-in-time recovery** enabled
- **Encryption at rest** with KMS
- **Fine-grained access control** via IAM
- **Resource tagging** for governance

### 3. KMS Key Management

KMS keys feature:

- **Automatic key rotation** enabled
- **Least privilege key policies**
- **Cross-account access** when needed
- **Audit logging** via CloudTrail

### 4. Network Security

Consider implementing:

- **VPC endpoints** for S3 and DynamoDB access
- **Private subnets** for Terraform execution
- **Security groups** limiting access

### 5. Access Control

Implement:

- **IAM roles** instead of users when possible
- **Principle of least privilege**
- **Multi-factor authentication** for sensitive operations
- **Regular access reviews**

## Troubleshooting

### Common Issues and Solutions

#### Issue: "Access Denied" During Setup

**Symptoms:**
```
ERROR: Failed to create S3 bucket: Access Denied
```

**Solutions:**
1. Check IAM permissions (see [Required IAM Permissions](#required-iam-permissions))
2. Verify AWS credentials: `aws sts get-caller-identity`
3. Check if bucket name already exists globally
4. Ensure region is specified correctly

#### Issue: "Bucket Already Exists" Error

**Symptoms:**
```
ERROR: Bucket name already exists in different region
```

**Solutions:**
1. S3 bucket names are globally unique
2. Choose a different naming pattern
3. Check if bucket exists in different region
4. Use `--dry-run` to verify naming before creation

#### Issue: DynamoDB Table Creation Fails

**Symptoms:**
```
ERROR: ResourceInUseException: Table already exists
```

**Solutions:**
1. Check if table exists: `aws dynamodb describe-table --table-name <table-name>`
2. Verify table region matches configuration
3. Use `--force` flag to skip existing resources

#### Issue: Cross-Account Role Assumption Fails

**Symptoms:**
```
ERROR: Failed to assume role: arn:aws:iam::123456789012:role/TerraformRole
```

**Solutions:**
1. Verify role exists and is assumable
2. Check trust relationship policy
3. Ensure external ID matches (if configured)
4. Verify cross-account permissions

#### Issue: KMS Key Access Denied

**Symptoms:**
```
ERROR: User is not authorized to perform: kms:Encrypt
```

**Solutions:**
1. Check KMS key policy
2. Verify IAM permissions for KMS operations
3. Ensure key is in correct region
4. Check if key is disabled or pending deletion

### Debug Mode

Enable debug mode for detailed troubleshooting:

```bash
# Script debug mode
./scripts/aws-setup.sh --debug --tenant fnx --account dev --environment testenv-01

# Workflow debug mode
atmos workflow bootstrap-backend tenant=fnx account=dev environment=testenv-01 debug=true
```

### Log Files

Check log files for detailed error information:

```bash
# Script logs
ls -la logs/aws-setup-*.log

# Atmos logs
ls -la logs/
```

## Multi-Environment Strategy

### Environment Separation Strategies

#### Strategy 1: Account-Based Separation

```
Production Account (111111111111):
├── fnx-prod-production-terraform-state
├── fnx-prod-production-terraform-locks
└── fnx-prod-staging-terraform-state

Development Account (222222222222):
├── fnx-dev-testenv-01-terraform-state
├── fnx-dev-testenv-02-terraform-state
└── fnx-dev-integration-terraform-state
```

#### Strategy 2: Region-Based Separation

```
US-East-1:
├── fnx-prod-production-terraform-state
└── fnx-dev-testenv-01-terraform-state

US-West-2:
├── fnx-prod-production-us-west-2-terraform-state
└── fnx-dev-testenv-01-us-west-2-terraform-state
```

#### Strategy 3: Tenant-Based Separation

```
Tenant FNX:
├── fnx-prod-production-terraform-state
├── fnx-dev-testenv-01-terraform-state
└── fnx-staging-staging-terraform-state

Tenant ABC:
├── abc-prod-production-terraform-state
├── abc-dev-testenv-01-terraform-state
└── abc-staging-staging-terraform-state
```

### Environment Configuration Examples

#### Development Environment

```bash
./scripts/aws-setup.sh \
  --tenant fnx \
  --account dev \
  --environment testenv-01 \
  --region us-east-1 \
  --enable-logging
```

#### Staging Environment

```bash
./scripts/aws-setup.sh \
  --tenant fnx \
  --account staging \
  --environment staging-01 \
  --region us-east-1 \
  --kms-key-id alias/staging-terraform-key
```

#### Production Environment

```bash
./scripts/aws-setup.sh \
  --tenant fnx \
  --account prod \
  --environment production \
  --region us-west-2 \
  --assume-role arn:aws:iam::PROD_ACCOUNT:role/TerraformRole \
  --kms-key-id alias/prod-terraform-key
```

### Naming Conventions

Follow these naming patterns for consistency:

```
S3 Buckets:
{tenant}-{account}-{environment}-terraform-state

DynamoDB Tables:
{tenant}-{account}-{environment}-terraform-locks

KMS Keys:
alias/{tenant}-{account}-{environment}-terraform-key

IAM Roles:
{tenant}-{account}-{environment}-terraform-role
```

## Monitoring and Maintenance

### CloudWatch Monitoring

Set up monitoring for:

#### S3 Bucket Metrics
- Number of objects
- Bucket size
- Request metrics
- Error rates

#### DynamoDB Metrics
- Read/write capacity utilization
- Throttling events
- Item count
- Storage utilization

#### KMS Metrics
- Key usage
- API request counts
- Error rates

### Automated Maintenance

#### State File Cleanup

```bash
# List old versions
aws s3api list-object-versions --bucket fnx-dev-testenv-01-terraform-state

# Clean up old versions (be careful!)
aws s3api delete-object --bucket fnx-dev-testenv-01-terraform-state --key terraform.tfstate --version-id <version-id>
```

#### Lock Cleanup

Create a Lambda function to clean up stale locks:

```python
import boto3
import json
from datetime import datetime, timedelta

def lambda_handler(event, context):
    dynamodb = boto3.resource('dynamodb')
    table = dynamodb.Table('fnx-dev-testenv-01-terraform-locks')
    
    # Delete locks older than 24 hours
    cutoff = datetime.utcnow() - timedelta(hours=24)
    
    response = table.scan()
    for item in response['Items']:
        created = datetime.fromisoformat(item.get('Created', ''))
        if created < cutoff:
            table.delete_item(Key={'LockID': item['LockID']})
    
    return {'statusCode': 200}
```

### Backup and Recovery

#### State File Backup

```bash
# Backup state files
aws s3 sync s3://fnx-prod-production-terraform-state ./backups/state/$(date +%Y%m%d)/

# Restore from backup
aws s3 sync ./backups/state/20240315/ s3://fnx-prod-production-terraform-state
```

#### Cross-Region Replication

Set up cross-region replication for disaster recovery:

```json
{
    "Role": "arn:aws:iam::123456789012:role/replication-role",
    "Rules": [
        {
            "ID": "ReplicateToSecondaryRegion",
            "Status": "Enabled",
            "Prefix": "",
            "Destination": {
                "Bucket": "arn:aws:s3:::fnx-prod-production-terraform-state-backup",
                "StorageClass": "STANDARD_IA"
            }
        }
    ]
}
```

### Cost Optimization

#### S3 Lifecycle Policies

Automatically implemented lifecycle policies:

```json
{
    "Rules": [
        {
            "ID": "terraform-state-lifecycle",
            "Status": "Enabled",
            "NoncurrentVersionTransitions": [
                {
                    "NoncurrentDays": 30,
                    "StorageClass": "STANDARD_IA"
                },
                {
                    "NoncurrentDays": 90,
                    "StorageClass": "GLACIER"
                }
            ],
            "NoncurrentVersionExpiration": {
                "NoncurrentDays": 365
            }
        }
    ]
}
```

#### DynamoDB Cost Optimization

- Use **PAY_PER_REQUEST** billing for low-traffic environments
- Consider **STANDARD_INFREQUENT_ACCESS** table class
- Enable **auto-scaling** for predictable workloads

#### Monitoring Costs

```bash
# Check S3 costs
aws ce get-cost-and-usage \
  --time-period Start=2024-01-01,End=2024-01-31 \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=SERVICE

# Check DynamoDB costs
aws ce get-cost-and-usage \
  --time-period Start=2024-01-01,End=2024-01-31 \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=SERVICE \
  --filter '{"Dimensions":{"Key":"SERVICE","Values":["Amazon DynamoDB"]}}'
```

## Verification Commands

Verify your backend setup:

```bash
# Verify backend infrastructure
atmos workflow bootstrap-backend verify tenant=fnx account=dev environment=testenv-01

# Check S3 bucket configuration
aws s3api get-bucket-versioning --bucket fnx-dev-testenv-01-terraform-state
aws s3api get-bucket-encryption --bucket fnx-dev-testenv-01-terraform-state

# Check DynamoDB table
aws dynamodb describe-table --table-name fnx-dev-testenv-01-terraform-locks
aws dynamodb describe-continuous-backups --table-name fnx-dev-testenv-01-terraform-locks

# Test state locking
terraform init && terraform plan
```

## Migration from Existing Backends

### From Local State

```bash
# Initialize with remote backend
terraform init

# Push existing state
terraform state push terraform.tfstate
```

### From Different Backend

```bash
# Create backend configuration
cat > backend.tf << EOF
terraform {
  backend "s3" {
    bucket         = "fnx-dev-testenv-01-terraform-state"
    key            = "terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "fnx-dev-testenv-01-terraform-locks"
    encrypt        = true
  }
}
EOF

# Migrate state
terraform init -migrate-state
```

## Support and Resources

### Documentation Links

- [Terraform S3 Backend](https://www.terraform.io/docs/backends/types/s3.html)
- [AWS S3 Security Best Practices](https://docs.aws.amazon.com/s3/latest/userguide/security-best-practices.html)
- [DynamoDB Best Practices](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/best-practices.html)

### Getting Help

1. Check the [troubleshooting section](#troubleshooting)
2. Review log files in the `logs/` directory
3. Run with `--debug` flag for detailed output
4. Verify AWS permissions and credentials
5. Check AWS service status and limits

### Contributing

To improve this setup:

1. Test changes in development environment first
2. Update documentation for any new features
3. Follow security best practices
4. Add appropriate error handling
5. Include monitoring and alerting

---

**Last Updated:** $(date -u +%Y-%m-%d)
**Version:** 1.0.0