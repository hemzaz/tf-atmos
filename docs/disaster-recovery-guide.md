# Disaster Recovery Guide for Atmos-Managed Infrastructure

_Last Updated: February 27, 2025_

This guide provides comprehensive procedures for backing up, protecting, and recovering your Atmos-managed infrastructure in the event of failures or disasters.

## Table of Contents

- [Introduction](#introduction)
- [Risk Assessment](#risk-assessment)
- [Backup Strategies](#backup-strategies)
- [Recovery Procedures](#recovery-procedures)
- [Testing and Validation](#testing-and-validation)
- [Incident Response](#incident-response)
- [Reference](#reference)

## Introduction

Disaster recovery (DR) is a critical aspect of infrastructure management. This guide provides strategies and procedures for recovering Atmos-managed infrastructure from various failure scenarios, including:

- Terraform state corruption or loss
- AWS account or resource compromise
- Infrastructure deployment failures
- Accidental resource deletion
- Region-wide AWS outages

The guide focuses on protecting and recovering the core components of your Atmos infrastructure:

1. Terraform state files
2. AWS resources
3. Configuration files
4. Access credentials and permissions

## Risk Assessment

Before implementing disaster recovery procedures, assess the potential risks and their impact:

| Risk | Likelihood | Impact | Mitigation Strategy |
|------|------------|--------|-------------------|
| Terraform state corruption | Medium | High | State versioning, regular backups |
| AWS account compromise | Low | Critical | IAM best practices, MFA, regular audits |
| Accidental resource deletion | High | Medium-High | State locking, resource protection, backup |
| Region-wide AWS outage | Low | High | Multi-region deployments |
| Code/configuration errors | High | Medium | Testing, validation, code review |
| DynamoDB lock table issues | Medium | Medium | Table backups, monitoring |

## Backup Strategies

### 1. Terraform State Backup

The Terraform state is stored in S3 with the following protective measures:

#### S3 Bucket Configuration

```hcl
resource "aws_s3_bucket" "terraform_state" {
  bucket = var.terraform_state_bucket
  
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
```

#### Backup Procedures

1. **Automated Daily Backups**: Configure replication to a backup bucket in another region:

```hcl
resource "aws_s3_bucket_replication_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  role   = aws_iam_role.replication.arn

  rule {
    id     = "backup-to-dr-region"
    status = "Enabled"

    destination {
      bucket        = aws_s3_bucket.terraform_state_backup.arn
      storage_class = "STANDARD"
    }
  }
}
```

2. **Periodic Exports**: Schedule regular exports of state to a secure location:

```bash
#!/bin/bash
# backup-terraform-state.sh
DATE=$(date +%Y-%m-%d)
mkdir -p backups/$DATE

# List all objects in the bucket
aws s3 ls s3://terraform-state-bucket/ --recursive | grep .tfstate > state_files.txt

# Download each state file
while read line; do
  file=$(echo $line | awk '{print $4}')
  dir=$(dirname backups/$DATE/$file)
  mkdir -p $dir
  aws s3 cp s3://terraform-state-bucket/$file backups/$DATE/$file
done < state_files.txt

# Compress backups
tar -czf backups/terraform-state-$DATE.tar.gz backups/$DATE
```

### 2. DynamoDB Lock Table Backup

```hcl
resource "aws_dynamodb_table" "terraform_locks" {
  name         = var.terraform_locks_table
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }
}
```

### 3. Configuration Backup

Store all Atmos configuration files in version-controlled repositories:

```bash
# Backup script for configurations
git add .
git commit -m "Configuration backup $(date)"
git push origin main
git tag "backup-$(date +%Y-%m-%d)"
git push --tags
```

### 4. Resource Backup

For critical resources, implement regular backups:

- **RDS Database Backups**:
  ```hcl
  resource "aws_db_instance" "database" {
    # ... other configuration ...
    backup_retention_period = 30
    backup_window           = "03:00-04:00"
  }
  ```

- **EBS Snapshot Lifecycle**:
  ```hcl
  resource "aws_dlm_lifecycle_policy" "ebs_snapshots" {
    description        = "EBS Snapshot Lifecycle Policy"
    execution_role_arn = aws_iam_role.dlm_lifecycle_role.arn
    
    policy_details {
      resource_types = ["VOLUME"]
      
      schedule {
        name = "Daily Snapshots"
        create_rule {
          interval      = 24
          times         = ["03:00"]
          interval_unit = "HOURS"
        }
        retain_rule {
          count = 14
        }
      }
    }
  }
  ```

## Recovery Procedures

### 1. Terraform State Recovery

#### From S3 Versioning

If the state file is corrupted or accidentally deleted:

```bash
# List available versions
aws s3api list-object-versions --bucket terraform-state-bucket --prefix path/to/state/terraform.tfstate

# Restore a specific version
aws s3api get-object --bucket terraform-state-bucket --key path/to/state/terraform.tfstate --version-id "VERSION_ID" restored-terraform.tfstate
```

#### From Backup Bucket

If the primary S3 bucket is unavailable:

```bash
# Configure Terraform to use the backup bucket temporarily
cat > backend.tf << EOF
terraform {
  backend "s3" {
    bucket         = "terraform-state-backup-bucket"
    key            = "path/to/state/terraform.tfstate"
    region         = "us-west-2"  # DR region
    dynamodb_table = "terraform-locks-backup"
  }
}
EOF

# Initialize with the new backend
terraform init -reconfigure
```

#### From Manual Backup

```bash
# Extract backup
tar -xzf backups/terraform-state-2023-01-01.tar.gz

# Copy state file back to S3
aws s3 cp backups/2023-01-01/path/to/state/terraform.tfstate s3://terraform-state-bucket/path/to/state/terraform.tfstate
```

### 2. DynamoDB Lock Recovery

#### Clear Stale Locks

```bash
# Identify locks
aws dynamodb scan --table-name terraform-locks --attributes-to-get LockID Info

# Delete stale lock
aws dynamodb delete-item --table-name terraform-locks --key '{"LockID": {"S": "LOCK_ID_VALUE"}}'
```

#### Restore From Backup

```bash
# Create a new table from PITR (Point-In-Time Recovery)
aws dynamodb restore-table-to-point-in-time \
  --source-table-name terraform-locks \
  --target-table-name terraform-locks-restored \
  --restore-date-time 2023-01-01T00:00:00Z

# Update backend configuration to use the restored table
```

### 3. Infrastructure Recovery

#### Complete Environment Recovery

```bash
# Step 1: Restore Terraform backend infrastructure
atmos workflow bootstrap-backend tenant=mycompany region=us-west-2

# Step 2: Import existing resources
atmos workflow import tenant=mycompany account=dev environment=testenv-01

# Step 3: Reapply all components
atmos workflow apply-environment tenant=mycompany account=dev environment=testenv-01
```

#### Individual Component Recovery

```bash
# Restore a specific component
atmos terraform import vpc -s mycompany-dev-testenv-01 aws_vpc.main vpc-12345678
atmos terraform apply vpc -s mycompany-dev-testenv-01
```

### 4. Cross-Region Recovery

For region-wide failures, recover in another region:

```bash
# Step 1: Update environment configuration
cat > stacks/account/dev/testenv-01/backend.yaml << EOF
import:
  - catalog/backend

vars:
  account: dev
  environment: testenv-01
  region: us-west-2  # DR region
  tenant: mycompany
EOF

# Step 2: Deploy backend in new region
atmos workflow apply-backend tenant=mycompany account=dev environment=testenv-01

# Step 3: Deploy infrastructure in new region
atmos workflow apply-environment tenant=mycompany account=dev environment=testenv-01
```

## Testing and Validation

Regularly test and validate your disaster recovery procedures:

### 1. Simulated State File Corruption

```bash
# Step 1: Create a backup
aws s3 cp s3://terraform-state-bucket/path/to/state/terraform.tfstate terraform.tfstate.backup

# Step 2: Corrupt the state file
aws s3 cp corrupted-terraform.tfstate s3://terraform-state-bucket/path/to/state/terraform.tfstate

# Step 3: Test recovery
# Follow state recovery procedures

# Step 4: Restore original state
aws s3 cp terraform.tfstate.backup s3://terraform-state-bucket/path/to/state/terraform.tfstate
```

### 2. Simulated Lock Table Issues

```bash
# Create a stuck lock
aws dynamodb put-item --table-name terraform-locks \
  --item '{"LockID": {"S": "test-lock"}, "Info": {"S": "Test lock for DR testing"}}'

# Test lock resolution
# Follow lock recovery procedures

# Clean up test lock
aws dynamodb delete-item --table-name terraform-locks --key '{"LockID": {"S": "test-lock"}}'
```

### 3. Cross-Region Recovery Test

Periodically test deploying to a backup region:

```bash
# Deploy a minimal test stack to the DR region
atmos terraform apply vpc -s mycompany-dev-testenv-01-dr --var region=us-west-2

# Verify functionality
atmos terraform output vpc -s mycompany-dev-testenv-01-dr

# Clean up test resources
atmos terraform destroy vpc -s mycompany-dev-testenv-01-dr
```

## Incident Response

### 1. Incident Response Plan

When a disaster occurs:

1. **Assess**: Determine the scope and impact of the issue
2. **Contain**: Prevent further damage or data loss
3. **Recover**: Execute the appropriate recovery procedures
4. **Review**: Document the incident and improve procedures

### 2. Communication Template

```
INCIDENT NOTIFICATION

Status: [Investigating/Recovering/Resolved]
Issue: [Brief description of the issue]
Impact: [Description of affected resources/services]
Actions Taken: [Summary of recovery steps taken]
ETA: [Estimated time to resolution]
Next Update: [Time of next update]
```

### 3. Post-Incident Review

After recovery, conduct a thorough review:

1. Document the incident timeline
2. Identify root causes
3. Evaluate the effectiveness of recovery procedures
4. Implement improvements to prevent recurrence

## Reference

### Key Backup Commands

| Resource | Backup Command | Recovery Command |
|----------|---------------|------------------|
| S3 State | `aws s3 cp s3://bucket/path local-path` | `aws s3 cp local-path s3://bucket/path` |
| DynamoDB | `aws dynamodb create-backup` | `aws dynamodb restore-table-from-backup` |
| EC2 | `aws ec2 create-snapshot` | `aws ec2 create-volume --snapshot-id` |
| RDS | `aws rds create-db-snapshot` | `aws rds restore-db-instance-from-db-snapshot` |

### Recovery Time Objectives (RTO)

| Component | RTO Target | Recovery Method |
|-----------|------------|----------------|
| Terraform Backend | 1 hour | S3 versioning, replicated bucket |
| Core Network | 4 hours | State import, automated deployment |
| Application Services | 8 hours | State import, automated deployment |
| Database Services | 4 hours | Restore from automated backups |

### Recovery Point Objectives (RPO)

| Component | RPO Target | Backup Frequency |
|-----------|------------|-----------------|
| Terraform State | 24 hours | Continuous (S3 versioning) |
| Configuration Files | 24 hours | On commit (Git) |
| Database Data | 24 hours | Daily automated backups |
| Application Data | 24 hours | Daily snapshots |

### Useful Links

- [AWS Disaster Recovery Documentation](https://aws.amazon.com/disaster-recovery/)
- [Terraform State Management Best Practices](https://www.terraform.io/docs/cloud/guides/recommended-practices/part1.html#state-management)
- [AWS Backup Service Documentation](https://aws.amazon.com/backup/)
- [DynamoDB Point-in-time Recovery](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/PointInTimeRecovery.html)