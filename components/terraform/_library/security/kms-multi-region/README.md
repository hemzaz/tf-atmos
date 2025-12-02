# KMS Multi-Region Module

Enterprise KMS key management with multi-region replication and automatic rotation.

## Overview

This module creates and manages AWS KMS keys with enterprise-grade features including:

- **Multi-Region Replication**: Automatic key replication across AWS regions
- **Automatic Key Rotation**: Annual key rotation for compliance
- **Least Privilege Policies**: Granular access control for administrators, users, and services
- **Alias Management**: Friendly names for keys
- **Grant-Based Access**: Temporary access delegation with conditions
- **CloudTrail Integration**: Full audit trail of key usage

## Features

- Single-region or multi-region KMS keys
- Automatic annual key rotation
- Customizable key policies with least privilege
- Key aliases for easy reference
- Grant-based temporary access delegation
- Support for symmetric and asymmetric keys
- Integration with AWS services (S3, EBS, RDS, etc.)
- Configurable deletion windows
- CloudTrail logging integration

## Usage

### Basic Example

```hcl
module "kms" {
  source = "../../_library/security/kms-multi-region"

  name_prefix = "acme-prod-data"
  description = "KMS key for production data encryption"

  enable_key_rotation = true

  key_administrators = [
    "arn:aws:iam::123456789012:role/admin"
  ]

  key_users = [
    "arn:aws:iam::123456789012:role/application"
  ]

  tags = {
    Environment = "production"
    Purpose     = "data-encryption"
  }
}
```

### Multi-Region Example

```hcl
module "kms_multi_region" {
  source = "../../_library/security/kms-multi-region"

  name_prefix     = "acme-prod-dr"
  description     = "Multi-region KMS key for disaster recovery"
  is_multi_region = true

  replica_regions = [
    "us-west-2",
    "eu-west-1"
  ]

  enable_key_rotation = true

  key_administrators = [
    "arn:aws:iam::123456789012:role/security-admin"
  ]

  key_users = [
    "arn:aws:iam::123456789012:role/backup-service"
  ]

  key_service_users = [
    "s3.amazonaws.com",
    "rds.amazonaws.com"
  ]

  tags = {
    Environment = "production"
    DR          = "enabled"
  }
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5.0 |
| aws | >= 5.0.0, < 6.0.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| name_prefix | Prefix for resource names | `string` | n/a | yes |
| description | Key description | `string` | `"Managed by Terraform"` | no |
| enable_key_rotation | Enable automatic rotation | `bool` | `true` | no |
| is_multi_region | Enable multi-region replication | `bool` | `false` | no |
| replica_regions | List of replica regions | `list(string)` | `[]` | no |
| key_administrators | IAM ARNs for administrators | `list(string)` | `[]` | no |
| key_users | IAM ARNs for users | `list(string)` | `[]` | no |
| key_service_users | AWS service principals | `list(string)` | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| key_id | KMS key ID |
| key_arn | KMS key ARN |
| key_alias_name | Key alias name |
| replica_keys | Map of replica keys by region |

## Cost Estimation

- **Single-Region Key**: $1/month
- **Multi-Region Key**: $1/month (primary) + $1/month per replica
- **API Requests**: $0.03 per 10,000 requests

**Example**: Multi-region key with 2 replicas = $3/month + API costs

## Security Best Practices

1. Always enable key rotation
2. Use least privilege policies
3. Separate administrator and user roles
4. Enable CloudTrail logging
5. Use encryption context for grants
6. Regular key policy audits
7. Monitor key usage with CloudWatch

## Examples

- [Basic](./examples/basic) - Single-region key with rotation
- [Advanced](./examples/advanced) - Key with grants and policies
- [Multi-Region](./examples/multi-region) - DR-enabled key with replicas
