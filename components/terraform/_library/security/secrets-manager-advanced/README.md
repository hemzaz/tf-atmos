# Secrets Manager Advanced Module

Advanced secrets management with automatic rotation and disaster recovery.

## Overview

Enterprise secrets management with:
- **Automatic Rotation**: Lambda-based rotation for RDS, API keys, and custom secrets
- **Cross-Account Access**: Share secrets across AWS accounts
- **Disaster Recovery**: Replica secrets in multiple regions
- **RDS/Aurora Integration**: Native database credential rotation
- **API Key Rotation**: Custom rotation for third-party services
- **Monitoring**: CloudWatch metrics and alarms

## Features

- Automatic secret rotation (RDS, Aurora, DocumentDB, custom)
- Multi-region secret replication for DR
- KMS encryption
- Lambda rotation functions (included)
- Cross-account access policies
- CloudWatch monitoring and alerting
- Replica secrets with independent KMS keys
- Comprehensive IAM policies

## Usage

### Basic Example

```hcl
module "secret" {
  source = "../../_library/security/secrets-manager-advanced"

  name_prefix = "acme-prod-api-key"
  description = "API key for external service"

  secret_string = jsonencode({
    api_key = "your-api-key"
    api_secret = "your-api-secret"
  })

  kms_key_id             = module.kms.key_id
  recovery_window_days   = 30

  tags = {
    Environment = "production"
  }
}
```

### RDS Rotation Example

```hcl
module "rds_secret" {
  source = "../../_library/security/secrets-manager-advanced"

  name_prefix = "acme-prod-rds"
  description = "RDS master password"

  secret_string = jsonencode({
    username = "admin"
    password = random_password.db.result
    engine   = "postgres"
    host     = aws_db_instance.main.address
    port     = 5432
  })

  enable_rotation        = true
  rotation_days          = 30
  create_rotation_lambda = true
  rotation_type          = "rds"
  rds_instance_arn       = aws_db_instance.main.arn

  replica_regions = ["us-west-2", "eu-west-1"]

  tags = {
    Environment = "production"
    Service     = "database"
  }
}
```

## Cost Estimation

- **Secret Storage**: $0.40/secret/month
- **API Calls**: $0.05 per 10,000 calls
- **Lambda Rotation**: ~$0.20/month
- **Replicas**: $0.40/replica/month

**Example**: 3 secrets with 2 replicas each = $3.60/month + API/Lambda costs

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5.0 |
| aws | >= 5.0.0, < 6.0.0 |

## Examples

- [Basic](./examples/basic) - Simple secret storage
- [Advanced](./examples/advanced) - Secret with custom rotation
- [RDS Rotation](./examples/rds-rotation) - Database credential rotation
