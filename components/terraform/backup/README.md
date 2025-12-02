# AWS Backup Component

This Terraform component implements comprehensive automated backup and disaster recovery using AWS Backup.

## Features

- **Multiple Backup Plans**: Daily, weekly, and monthly backup schedules
- **Cross-Region Replication**: Optional backup replication to secondary region
- **Lifecycle Management**: Automatic transition to cold storage and deletion
- **Vault Lock**: Compliance-mode immutable backups
- **Multi-Resource Support**:
  - RDS databases
  - DynamoDB tables
  - EFS file systems
  - EC2 instances (tag-based)
  - EBS volumes
- **Notifications**: SNS alerts for backup/restore job status
- **Reporting**: Automated backup compliance reports
- **Testing**: Optional automated backup restoration testing

## Usage

```hcl
module "backup" {
  source = "../../components/terraform/backup"

  region = "us-east-1"

  rds_instances     = ["production-db-1", "production-db-2"]
  dynamodb_tables   = ["users", "orders", "products"]
  efs_file_systems  = ["fs-12345678"]

  enable_ec2_backup = true
  enable_ebs_backup = true

  enable_cross_region_backup = true
  replica_region            = "us-west-2"

  daily_retention_days   = 7
  weekly_retention_days  = 30
  monthly_retention_days = 365

  enable_backup_notifications = true
  notification_emails = [
    "ops-team@example.com"
  ]

  enable_backup_reports = true
  backup_reports_bucket = "backup-reports-bucket"

  enable_backup_testing   = true
  backup_testing_schedule = "cron(0 5 ? * MON *)"

  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}
```

## Backup Schedules

- **Daily**: 2:00 AM UTC, retained for 7 days
- **Weekly**: Sunday 3:00 AM UTC, retained for 30 days
- **Monthly**: 1st of month 4:00 AM UTC, retained for 365 days

## Retention Policies

| Backup Type | Default Retention | Cold Storage Transition | Compliance Lock |
|-------------|------------------|------------------------|-----------------|
| Daily       | 7 days           | Optional               | Optional        |
| Weekly      | 30 days          | Optional               | Optional        |
| Monthly     | 365 days         | 90 days                | Optional        |

## Backup Testing

Enable automated backup testing to verify restore functionality:

```hcl
enable_backup_testing   = true
backup_testing_schedule = "cron(0 5 ? * MON *)"
```

The testing Lambda function:
- Selects random recovery points
- Initiates restore jobs to isolated environment
- Validates restored resources
- Cleans up test resources
- Reports results via SNS

## Cross-Region Disaster Recovery

Enable cross-region backup for disaster recovery:

```hcl
enable_cross_region_backup = true
replica_region            = "us-west-2"
replica_kms_key_arn       = "arn:aws:kms:us-west-2:..."
```

## Compliance and Security

- **Encryption**: All backups encrypted with KMS
- **Vault Lock**: Immutable backups for compliance (WORM)
- **Access Control**: IAM policies restrict backup access
- **Audit Trail**: CloudTrail logs all backup operations
- **Reporting**: Compliance reports for audit

## Cost Optimization

- **Lifecycle Policies**: Automatic cold storage transition
- **Retention Management**: Configurable retention periods
- **Tag-Based Selection**: Backup only tagged resources
- **Archive Tier**: Long-term archival for compliance

## Monitoring

CloudWatch alarms monitor:
- Backup job failures
- Restore job failures
- Vault capacity
- Cross-region replication status

## Recovery Procedures

### RDS Recovery
```bash
aws backup start-restore-job \
  --recovery-point-arn <recovery-point-arn> \
  --metadata DBInstanceIdentifier=restored-db-instance
```

### EC2 Recovery
```bash
aws backup start-restore-job \
  --recovery-point-arn <recovery-point-arn> \
  --metadata InstanceType=t3.medium,SubnetId=subnet-xxx
```

## Best Practices

1. **Test Restores Regularly**: Enable automated testing or perform manual restore tests monthly
2. **Monitor Backup Status**: Subscribe to SNS notifications
3. **Cross-Region Replication**: Enable for production workloads
4. **Vault Lock**: Enable for compliance requirements (HIPAA, PCI-DSS)
5. **Tag Resources**: Use `Backup=true` tag for EC2/EBS backups
6. **Review Reports**: Regularly review backup compliance reports
7. **Optimize Costs**: Use cold storage for long-term retention
8. **Document RPO/RTO**: Define and test recovery objectives

## Recovery Objectives

- **RPO (Recovery Point Objective)**: 24 hours (daily backups)
- **RTO (Recovery Time Objective)**: Varies by resource type
  - RDS: 1-2 hours
  - EC2: 30-60 minutes
  - EFS: 15-30 minutes
  - DynamoDB: 30-60 minutes

## Compliance Standards

This component supports compliance with:
- SOC 2
- HIPAA
- PCI-DSS
- GDPR (data protection requirements)
- ISO 27001
