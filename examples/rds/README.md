# RDS Database Examples

This directory contains examples for deploying and configuring Amazon RDS databases using the Atmos framework.

## Basic PostgreSQL RDS Instance

Below is an example of how to deploy a basic PostgreSQL RDS instance:

```yaml
# Stack configuration (environment.yaml)
components:
  terraform:
    rds/postgresql:
      vars:
        enabled: true
        region: us-west-2
        
        # Database Engine Configuration
        engine: "postgres"
        engine_version: "14.7"
        major_engine_version: "14"
        instance_class: "db.t3.medium"
        allocated_storage: 20
        max_allocated_storage: 100
        
        # Database Settings
        database_name: "appdb"
        database_user: "dbadmin"
        database_password: "${ssm:/path/to/db/password}"
        database_port: 5432
        
        # Backup Configuration
        backup_retention_period: 7
        backup_window: "03:00-04:00"
        maintenance_window: "sun:04:30-sun:05:30"
        
        # Network Configuration
        subnet_ids: ${dep.vpc.outputs.database_subnet_ids}
        vpc_id: ${dep.vpc.outputs.vpc_id}
        allowed_security_group_ids: [
          ${dep.securitygroup.outputs.app_security_group_id}
        ]
        
        # General Settings
        multi_az: false
        storage_encrypted: true
        deletion_protection: true
        skip_final_snapshot: false
        final_snapshot_identifier: "appdb-final-snapshot"
        
        # Tags
        tags:
          Environment: dev
          Project: demo
```

## Production-Ready MySQL RDS Instance

For production workloads requiring high availability and monitoring:

```yaml
# Stack configuration (environment.yaml)
components:
  terraform:
    rds/mysql:
      vars:
        enabled: true
        region: us-west-2
        
        # Database Engine Configuration
        engine: "mysql"
        engine_version: "8.0.32"
        major_engine_version: "8.0"
        instance_class: "db.r5.large"
        allocated_storage: 100
        max_allocated_storage: 500
        
        # Database Settings
        database_name: "production"
        database_user: "admin"
        database_password: "${ssm:/production/db/password}"
        database_port: 3306
        
        # High Availability Configuration
        multi_az: true
        storage_encrypted: true
        kms_key_id: "arn:aws:kms:us-west-2:123456789012:key/abcd1234-a123-456a-a12b-a123b4cd56ef"
        
        # Performance Configuration
        parameters: [
          {
            name: "innodb_buffer_pool_size",
            value: "{DBInstanceClassMemory*3/4}"
          },
          {
            name: "max_connections",
            value: "1000"
          }
        ]
        
        # Backup Configuration
        backup_retention_period: 30
        backup_window: "02:00-03:00"
        maintenance_window: "sun:03:30-sun:04:30"
        
        # Network Configuration
        subnet_ids: ${dep.vpc.outputs.database_subnet_ids}
        vpc_id: ${dep.vpc.outputs.vpc_id}
        allowed_security_group_ids: [
          ${dep.securitygroup.outputs.app_security_group_id}
        ]
        
        # Enhanced Monitoring
        monitoring_interval: 30
        create_monitoring_role: true
        
        # Protection Settings
        deletion_protection: true
        skip_final_snapshot: false
        final_snapshot_identifier: "prod-db-final-snapshot"
        
        # Tags
        tags:
          Environment: production
          Project: core-services
```

## Aurora PostgreSQL Cluster

For applications requiring a managed database cluster with automatic scaling:

```yaml
# Stack configuration (environment.yaml)
components:
  terraform:
    rds/aurora:
      vars:
        enabled: true
        region: us-west-2
        
        # Cluster Configuration
        engine: "aurora-postgresql"
        engine_version: "14.7"
        instance_class: "db.r5.large"
        
        # Cluster Scaling
        cluster_size: 2
        autoscaling_enabled: true
        autoscaling_min_capacity: 1
        autoscaling_max_capacity: 5
        
        # Database Settings
        database_name: "analytics"
        database_user: "admin"
        database_password: "${ssm:/analytics/db/password}"
        database_port: 5432
        
        # Storage Configuration
        storage_encrypted: true
        kms_key_id: "arn:aws:kms:us-west-2:123456789012:key/abcd1234-a123-456a-a12b-a123b4cd56ef"
        
        # Backup Configuration
        backup_retention_period: 14
        preferred_backup_window: "02:00-03:00"
        preferred_maintenance_window: "sun:03:30-sun:04:30"
        
        # Network Configuration
        subnet_ids: ${dep.vpc.outputs.database_subnet_ids}
        vpc_id: ${dep.vpc.outputs.vpc_id}
        allowed_security_group_ids: [
          ${dep.securitygroup.outputs.analytics_security_group_id}
        ]
        
        # Enhanced Monitoring
        monitoring_interval: 30
        create_monitoring_role: true
        
        # Tags
        tags:
          Environment: production
          Project: analytics
```

## Implementation Notes

1. **Security Best Practices**:
   - Always store database passwords in SSM Parameter Store or Secrets Manager
   - Enable storage encryption for all database instances
   - Use VPC security groups to restrict access
   - Enable deletion protection for production databases

2. **High Availability Considerations**:
   - Use Multi-AZ deployments for production workloads
   - Consider Aurora for mission-critical applications requiring automatic scaling
   - Implement a proper backup strategy with appropriate retention periods

3. **Performance Tuning**:
   - Choose appropriate instance classes based on workload requirements
   - Configure custom parameter groups for specific database tuning
   - Enable enhanced monitoring for production instances
   - Set appropriate allocated storage with room for growth

4. **Cost Optimization**:
   - Use smaller instance classes for development/testing
   - Disable Multi-AZ for non-production environments
   - Consider RDS Reserved Instances for production workloads