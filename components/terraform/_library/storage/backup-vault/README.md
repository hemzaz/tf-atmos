# Backup Vault Module

Production-ready AWS Backup vault with KMS encryption, lifecycle rules, cross-region backup, and compliance reporting.

## Features

- AWS Backup vault with KMS encryption
- Flexible backup plans for multiple resource types (EBS, RDS, EFS, DynamoDB)
- Lifecycle management (cold storage transition, retention policies)
- Cross-region backup copy with independent lifecycle
- SNS notifications for backup events
- Vault lock for compliance (WORM protection)
- Tag-based or resource-based backup selection
- Continuous backup support for point-in-time recovery
- CloudWatch alarms for backup job monitoring
- IAM role with least privilege access

## Usage

```hcl
module "backup_vault" {
  source = "../../_library/storage/backup-vault"

  name_prefix = "myapp"
  environment = "production"

  enable_notifications    = true
  notification_endpoints  = ["ops-team@example.com"]

  backup_plans = {
    critical = {
      rules = [
        {
          name     = "hourly-backup"
          schedule = "cron(0 * * * ? *)"
          lifecycle = {
            delete_after       = 7
            cold_storage_after = null
          }
          enable_continuous_backup = true
        },
        {
          name     = "daily-backup"
          schedule = "cron(0 5 * * ? *)"
          lifecycle = {
            delete_after       = 35
            cold_storage_after = 30
          }
        }
      ]
      selection_tags = [
        {
          key   = "Backup"
          value = "critical"
        }
      ]
    }
  }

  enable_vault_lock = true
  vault_lock_min_retention_days = 7

  tags = {
    Compliance = "SOC2"
  }
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5.0 |
| aws | >= 5.0.0 |

## Inputs

See `variables.tf` for all available inputs.

## Outputs

See `outputs.tf` for all available outputs.
