# RDS Component

_Last Updated: February 28, 2025_

## Overview

The RDS component provisions and manages AWS RDS databases for different database engines, with built-in security, backup, and monitoring features.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        AWS VPC                               │
│                                                             │
│  ┌─────────────────────┐      ┌────────────────────────┐    │
│  │                     │      │                        │    │
│  │   Application       │      │   Database Subnets     │    │
│  │   Tier              │      │   (Multi-AZ)           │    │
│  │                     │      │                        │    │
│  │   ┌─────────────┐   │      │   ┌───────────────┐    │    │
│  │   │             │   │      │   │               │    │    │
│  │   │ Application ├───┼──────┼──►│ RDS Instance  │    │    │
│  │   │ Servers     │   │      │   │               │    │    │
│  │   │             │   │      │   └───────┬───────┘    │    │
│  │   └─────────────┘   │      │           │            │    │
│  │                     │      │   ┌───────▼───────┐    │    │
│  │                     │      │   │               │    │    │
│  │                     │      │   │ Security      │    │    │
│  │                     │      │   │ Group         │    │    │
│  │                     │      │   │               │    │    │
│  └─────────────────────┘      └───┬────────────────────┘    │
│                                   │                         │
└───────────────────────────────────┼─────────────────────────┘
                                    │
    ┌─────────────────┐       ┌─────▼──────────┐      ┌─────────────────┐
    │                 │       │                │      │                 │
    │  AWS Secrets    │◄──────┤ AWS KMS        │      │ CloudWatch      │
    │  Manager        │       │ Encryption     │      │ Monitoring      │
    │                 │       │                │      │                 │
    └─────────────────┘       └────────────────┘      └─────────────────┘
```

## Features

- Provisions single RDS instances for MySQL, PostgreSQL, MariaDB, Oracle, and SQL Server
- Creates and manages security groups with proper ingress/egress rules
- Provisions subnet groups for proper network placement
- Creates parameter groups for database engine tuning
- Automatically generates and securely stores credentials in AWS Secrets Manager
- Configures enhanced monitoring with custom IAM roles
- Supports encryption at rest with KMS
- Implements automated backups and maintenance windows
- Configures high availability with Multi-AZ deployments
- Supports performance insights for advanced database performance monitoring
- Implements proper security measures with deletion protection

## Usage

To use the RDS component in your stack, include it in your component configuration:

```yaml
# Stack configuration (environment.yaml)
components:
  terraform:
    rds:
      vars:
        region: us-west-2
        vpc_id: ${dep.vpc.outputs.vpc_id}
        vpc_cidr: ${dep.vpc.outputs.vpc_cidr_block}
        subnet_ids: ${dep.vpc.outputs.database_subnet_ids}
        allowed_security_groups: 
          - ${dep.securitygroup.outputs.app_security_group_id}
        
        # Database Configuration
        identifier: "app-db"
        engine: "mysql"
        engine_version: "8.0.32"
        family: "mysql8.0"
        instance_class: "db.t3.medium"
        allocated_storage: 50
        max_allocated_storage: 100
        storage_type: "gp3"
        storage_encrypted: true
        db_name: "appdb"
        username: "admin"
        port: 3306
        
        # Parameter Group Configuration
        parameters:
          - name: "max_connections"
            value: "200"
          - name: "innodb_buffer_pool_size"
            value: "{DBInstanceClassMemory*3/4}"
        
        # High Availability Configuration
        multi_az: true
        
        # Backup Configuration
        backup_retention_period: 7
        backup_window: "03:00-04:00"
        maintenance_window: "sun:04:30-sun:05:30"
        
        # Monitoring Configuration
        monitoring_interval: 60
        create_monitoring_role: true
        performance_insights_enabled: true
        
        # Protection Configuration
        deletion_protection: true
        prevent_destroy: true
        
        # Tags
        tags:
          Environment: dev
          Service: app-database
          Owner: "DevOps Team"
          Project: "Example Project"
          ManagedBy: "Terraform"
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| region | AWS region | `string` | n/a | yes |
| vpc_id | VPC ID where RDS instance will be created | `string` | n/a | yes |
| vpc_cidr | VPC CIDR block for security group egress rules | `string` | n/a | yes |
| subnet_ids | List of subnet IDs for the DB subnet group | `list(string)` | n/a | yes |
| allowed_security_groups | List of security group IDs allowed to connect to the RDS instance | `list(string)` | `[]` | no |
| identifier | Identifier for the RDS instance | `string` | n/a | yes |
| engine | Database engine type | `string` | `"mysql"` | no |
| engine_version | Database engine version | `string` | `"8.0"` | no |
| family | Database parameter group family | `string` | `"mysql8.0"` | no |
| instance_class | Instance class for the RDS instance | `string` | `"db.t3.small"` | no |
| allocated_storage | Allocated storage size in GB | `number` | `20` | no |
| max_allocated_storage | Maximum storage size in GB for autoscaling | `number` | `100` | no |
| storage_type | Storage type for the RDS instance | `string` | `"gp2"` | no |
| storage_encrypted | Enable storage encryption | `bool` | `true` | no |
| kms_key_id | KMS key ID for storage encryption | `string` | `null` | no |
| username | Username for the database | `string` | `"admin"` | no |
| port | Port for the database | `number` | `3306` | no |
| db_name | Name of the database | `string` | n/a | yes |
| parameters | List of DB parameters to set | `list(object({ name = string, value = string }))` | `[]` | no |
| availability_zone | Availability zone for the RDS instance | `string` | `null` | no |
| multi_az | Enable Multi-AZ deployment | `bool` | `false` | no |
| publicly_accessible | Make the RDS instance publicly accessible | `bool` | `false` | no |
| allow_major_version_upgrade | Allow major version upgrades | `bool` | `false` | no |
| auto_minor_version_upgrade | Enable automatic minor version upgrades | `bool` | `true` | no |
| backup_retention_period | Backup retention period in days | `number` | `7` | no |
| backup_window | Daily backup window time | `string` | `"03:00-06:00"` | no |
| maintenance_window | Weekly maintenance window time | `string` | `"Sun:00:00-Sun:03:00"` | no |
| skip_final_snapshot | Skip final snapshot when deleting the RDS instance | `bool` | `false` | no |
| copy_tags_to_snapshot | Copy tags to backups and snapshots | `bool` | `true` | no |
| monitoring_interval | Enhanced monitoring interval in seconds (0 to disable) | `number` | `60` | no |
| monitoring_role_arn | ARN of the IAM role for enhanced monitoring | `string` | `null` | no |
| create_monitoring_role | Create an IAM role for RDS enhanced monitoring | `bool` | `true` | no |
| performance_insights_enabled | Enable Performance Insights | `bool` | `true` | no |
| deletion_protection | Enable deletion protection | `bool` | `true` | no |
| prevent_destroy | Prevent destroy of the RDS instance through the lifecycle | `bool` | `true` | no |
| additional_egress_rules | List of additional egress rules for the RDS security group | `list(object)` | `[]` | no |
| tags | Tags to apply to resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| instance_id | ID of the RDS instance |
| instance_address | Address of the RDS instance |
| instance_endpoint | Endpoint of the RDS instance |
| instance_name | Name of the database |
| security_group_id | ID of the RDS security group |
| subnet_group_id | ID of the RDS subnet group |
| parameter_group_id | ID of the RDS parameter group |
| password_secret_arn | ARN of the Secrets Manager secret for the RDS password |

## Examples

### MySQL Database

```yaml
# Stack configuration (environment.yaml)
components:
  terraform:
    rds/mysql:
      vars:
        region: us-west-2
        vpc_id: ${dep.vpc.outputs.vpc_id}
        vpc_cidr: ${dep.vpc.outputs.vpc_cidr_block}
        subnet_ids: ${dep.vpc.outputs.database_subnet_ids}
        allowed_security_groups: 
          - ${dep.securitygroup.outputs.app_security_group_id}
        
        identifier: "mysql-db"
        engine: "mysql"
        engine_version: "8.0.32"
        family: "mysql8.0"
        instance_class: "db.t3.medium"
        allocated_storage: 50
        max_allocated_storage: 100
        storage_type: "gp3"
        storage_encrypted: true
        
        db_name: "appdb"
        username: "admin"
        port: 3306
        
        parameters:
          - name: "max_connections"
            value: "200"
          - name: "innodb_buffer_pool_size"
            value: "{DBInstanceClassMemory*3/4}"
        
        multi_az: false
        backup_retention_period: 7
        
        tags:
          Environment: dev
          Service: app-database
```

### Production PostgreSQL with HA

```yaml
# Stack configuration (environment.yaml)
components:
  terraform:
    rds/postgres:
      vars:
        region: us-west-2
        vpc_id: ${dep.vpc.outputs.vpc_id}
        vpc_cidr: ${dep.vpc.outputs.vpc_cidr_block}
        subnet_ids: ${dep.vpc.outputs.database_subnet_ids}
        allowed_security_groups: 
          - ${dep.securitygroup.outputs.app_security_group_id}
        
        identifier: "postgres-prod"
        engine: "postgres"
        engine_version: "14.7"
        family: "postgres14"
        instance_class: "db.r5.large"
        allocated_storage: 200
        max_allocated_storage: 500
        storage_type: "gp3"
        storage_encrypted: true
        kms_key_id: ${dep.kms.outputs.database_key_arn}
        
        db_name: "production"
        username: "admin"
        port: 5432
        
        parameters:
          - name: "max_connections"
            value: "500"
          - name: "shared_buffers"
            value: "{DBInstanceClassMemory/32768}"
          - name: "effective_cache_size"
            value: "{DBInstanceClassMemory/16384}"
        
        multi_az: true
        backup_retention_period: 30
        backup_window: "02:00-03:00"
        maintenance_window: "sun:03:30-sun:04:30"
        
        monitoring_interval: 30
        create_monitoring_role: true
        performance_insights_enabled: true
        
        deletion_protection: true
        prevent_destroy: true
        skip_final_snapshot: false
        
        tags:
          Environment: production
          Service: production-database
```

## Best Practices

### Security

- **Credential Management**: The component automatically generates a secure password and stores it in AWS Secrets Manager, avoiding plain text credentials in configuration.
- **Network Security**: Place RDS instances in private subnets and control access with security groups.
- **Encryption**: Enable storage encryption with KMS for all production databases.
- **IAM Authentication**: Consider enabling IAM authentication for more secure database access.
- **Auditing**: Enable database auditing features for compliance and security monitoring.

### High Availability

- Use Multi-AZ deployments for production databases to ensure failover capability.
- Configure appropriate backup retention periods based on recovery needs.
- Test database recovery procedures regularly to ensure they work as expected.
- Consider cross-region read replicas for additional disaster recovery capabilities.

### Performance

- Select instance types based on workload characteristics (memory-optimized for in-memory operations, storage-optimized for I/O-intensive workloads).
- Configure parameter groups to optimize for your specific workload.
- Use gp3 storage for better cost/performance balance or Provisioned IOPS for I/O-intensive workloads.
- Enable Performance Insights for production databases to identify performance bottlenecks.

### Cost Optimization

- Use Auto Scaling storage to automatically adjust capacity as needed.
- Consider Reserved Instances for production databases to reduce costs.
- Schedule development/test databases to stop during non-working hours.
- Monitor performance to right-size instances and avoid overprovisioning.

## Troubleshooting

### Common Issues

1. **Cannot connect to database**:
   - Verify security group rules allow traffic from your application security group.
   - Check that the database is in the correct subnets.
   - Verify that route tables are configured correctly.
   - Ensure credentials are correct and accessible.

2. **Performance issues**:
   - Check CloudWatch metrics for CPU, memory, and I/O bottlenecks.
   - Review Performance Insights data for query performance issues.
   - Verify parameter group settings are appropriate for workload.
   - Consider scaling instance class or storage type.

3. **Backup/restore issues**:
   - Check that backup retention period is properly configured.
   - Verify IAM permissions for snapshot operations.
   - For point-in-time recovery, ensure transaction logs are being captured.

4. **Cannot delete database**:
   - Check if deletion protection is enabled (intended safeguard).
   - Verify that `prevent_destroy` lifecycle setting is not blocking deletion.
   - Ensure IAM permissions allow deletion operations.

## Related Resources

- [AWS RDS Documentation](https://docs.aws.amazon.com/rds/index.html)
- [RDS Best Practices](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_BestPractices.html)
- [RDS Pricing](https://aws.amazon.com/rds/pricing/)
- [RDS Parameter Groups](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_WorkingWithParamGroups.html)
- [RDS Backup and Restore](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_CommonTasks.BackupRestore.html)
- [RDS Performance Insights](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_PerfInsights.html)