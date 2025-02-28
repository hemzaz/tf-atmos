# RDS Component

This component provisions and manages AWS RDS databases, including MySQL, PostgreSQL, SQL Server, and Aurora clusters.

## Features

- Create and manage RDS instances and Aurora clusters
- Configure security groups and network settings
- Set up automated backups and snapshots
- Configure parameter groups for database tuning
- Implement encryption with KMS
- Set up monitoring and alarms
- Configure multi-AZ deployment for high availability
- Manage database users and passwords securely

## Usage

```hcl
module "rds" {
  source = "git::https://github.com/example/tf-atmos.git//components/terraform/rds"
  
  region = var.region
  
  # Database Instances
  instances = {
    "primary-db" = {
      identifier          = "app-primary-db"
      engine              = "postgres"
      engine_version      = "14.7"
      instance_class      = "db.t3.large"
      allocated_storage   = 100
      storage_type        = "gp3"
      storage_encrypted   = true
      kms_key_id          = "arn:aws:kms:us-west-2:123456789012:key/abcd1234-a123-456a-a12b-a123b4cd56ef"
      
      # Database configuration
      db_name             = "appdb"
      username            = "admin"
      password            = "Password123!" # In production, use SSM or Secrets Manager
      port                = 5432
      
      # Network configuration
      subnet_group_name   = "rds-subnet-group"
      vpc_security_group_ids = ["sg-12345678"]
      
      # Backup configuration
      backup_retention_period = 7
      backup_window       = "03:00-04:00"
      maintenance_window  = "sun:04:30-sun:05:30"
      
      # High availability
      multi_az            = true
      
      # Monitoring
      monitoring_interval = 60
      monitoring_role_arn = "arn:aws:iam::123456789012:role/rds-monitoring-role"
      
      # Parameter group
      parameter_group_name = "postgres14-custom"
      
      # Tags
      tags = {
        Environment = "production"
        Service     = "user-database"
      }
    }
  }
  
  # Aurora Clusters
  aurora_clusters = {
    "analytics-cluster" = {
      cluster_identifier      = "analytics-cluster"
      engine                  = "aurora-postgresql"
      engine_version          = "14.7"
      database_name           = "analytics"
      master_username         = "admin"
      master_password         = "Password123!" # In production, use SSM or Secrets Manager
      
      # Network configuration
      vpc_security_group_ids  = ["sg-12345678"]
      db_subnet_group_name    = "aurora-subnet-group"
      
      # Backup configuration
      backup_retention_period = 14
      preferred_backup_window = "02:00-03:00"
      preferred_maintenance_window = "sun:03:30-sun:04:30"
      
      # Instances configuration
      instances = {
        "writer" = {
          identifier          = "analytics-writer"
          instance_class      = "db.r5.large"
          publicly_accessible = false
        },
        "reader-1" = {
          identifier          = "analytics-reader-1"
          instance_class      = "db.r5.large"
          publicly_accessible = false
        },
        "reader-2" = {
          identifier          = "analytics-reader-2"
          instance_class      = "db.r5.large"
          publicly_accessible = false
        }
      }
      
      # Scaling configuration
      auto_minor_version_upgrade = true
      
      # Encryption
      storage_encrypted   = true
      kms_key_id          = "arn:aws:kms:us-west-2:123456789012:key/abcd1234-a123-456a-a12b-a123b4cd56ef"
      
      # Parameter group
      db_cluster_parameter_group_name = "aurora-pg14-custom"
      
      # Tags
      tags = {
        Environment = "production"
        Service     = "analytics"
      }
    }
  }
  
  # Parameter Groups
  parameter_groups = {
    "postgres14-custom" = {
      name        = "postgres14-custom"
      family      = "postgres14"
      description = "Custom parameter group for PostgreSQL 14"
      parameters  = [
        {
          name  = "max_connections"
          value = "200"
        },
        {
          name  = "shared_buffers"
          value = "{DBInstanceClassMemory/32768}"
        }
      ]
      tags = {
        Environment = "production"
      }
    }
  }
  
  # Subnet Groups
  subnet_groups = {
    "primary-subnet-group" = {
      name        = "primary-subnet-group"
      description = "Subnet group for primary database"
      subnet_ids  = ["subnet-12345678", "subnet-87654321"]
      tags = {
        Environment = "production"
      }
    }
  }
  
  # Global Tags
  tags = {
    Project     = "example"
    ManagedBy   = "terraform"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| region | AWS region | `string` | n/a | yes |
| instances | Map of RDS instance configurations | `map(any)` | `{}` | no |
| aurora_clusters | Map of Aurora cluster configurations | `map(any)` | `{}` | no |
| parameter_groups | Map of DB parameter group configurations | `map(any)` | `{}` | no |
| subnet_groups | Map of DB subnet group configurations | `map(any)` | `{}` | no |
| option_groups | Map of DB option group configurations | `map(any)` | `{}` | no |
| create_security_group | Whether to create a security group for the instances | `bool` | `false` | no |
| security_group_rules | List of security group rules to add to the instance security group | `list(any)` | `[]` | no |
| tags | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| instance_endpoints | Map of RDS instance identifiers to their endpoints |
| instance_addresses | Map of RDS instance identifiers to their addresses |
| instance_ids | Map of RDS instance identifiers to their IDs |
| instance_arns | Map of RDS instance identifiers to their ARNs |
| cluster_endpoints | Map of Aurora cluster identifiers to their endpoints |
| cluster_reader_endpoints | Map of Aurora cluster identifiers to their reader endpoints |
| cluster_ids | Map of Aurora cluster identifiers to their IDs |
| cluster_arns | Map of Aurora cluster identifiers to their ARNs |
| parameter_group_ids | Map of parameter group names to their IDs |
| subnet_group_ids | Map of subnet group names to their IDs |

## Examples

### Basic MySQL RDS Instance

```yaml
# Stack configuration (environment.yaml)
components:
  terraform:
    rds/mysql:
      vars:
        region: us-west-2
        
        # Subnet Group
        subnet_groups:
          primary:
            name: "mysql-subnet-group"
            description: "Subnet group for MySQL database"
            subnet_ids: ${dep.vpc.outputs.database_subnet_ids}
        
        # Parameter Group
        parameter_groups:
          mysql8:
            name: "mysql8-custom"
            family: "mysql8.0"
            description: "Custom parameter group for MySQL 8.0"
            parameters:
              - name: "max_connections"
                value: "200"
              - name: "innodb_buffer_pool_size"
                value: "{DBInstanceClassMemory*3/4}"
        
        # Database Instance
        instances:
          main:
            identifier: "app-mysql-db"
            engine: "mysql"
            engine_version: "8.0.32"
            instance_class: "db.t3.medium"
            allocated_storage: 50
            max_allocated_storage: 100
            storage_type: "gp3"
            storage_encrypted: true
            
            # Database configuration
            db_name: "appdb"
            username: "admin"
            password: "${ssm:/db/password}"
            port: 3306
            
            # Network configuration
            subnet_group_name: "mysql-subnet-group"
            vpc_security_group_ids: [${dep.securitygroup.outputs.db_security_group_id}]
            
            # Backup configuration
            backup_retention_period: 7
            backup_window: "03:00-04:00"
            maintenance_window: "sun:04:30-sun:05:30"
            
            # High availability
            multi_az: false
            
            # Parameter group
            parameter_group_name: "mysql8-custom"
            
            # Tags
            tags:
              Environment: dev
              Service: app-database
```

### Production PostgreSQL RDS with High Availability

```yaml
# Stack configuration (environment.yaml)
components:
  terraform:
    rds/postgres:
      vars:
        region: us-west-2
        
        # Subnet Group
        subnet_groups:
          primary:
            name: "postgres-subnet-group"
            description: "Subnet group for PostgreSQL database"
            subnet_ids: ${dep.vpc.outputs.database_subnet_ids}
        
        # Parameter Group
        parameter_groups:
          postgres14:
            name: "postgres14-custom"
            family: "postgres14"
            description: "Custom parameter group for PostgreSQL 14"
            parameters:
              - name: "max_connections"
                value: "500"
              - name: "shared_buffers"
                value: "{DBInstanceClassMemory/32768}"
              - name: "effective_cache_size"
                value: "{DBInstanceClassMemory/16384}"
        
        # Database Instance
        instances:
          main:
            identifier: "production-postgres-db"
            engine: "postgres"
            engine_version: "14.7"
            instance_class: "db.r5.large"
            allocated_storage: 200
            max_allocated_storage: 500
            storage_type: "gp3"
            storage_encrypted: true
            kms_key_id: ${dep.kms.outputs.database_key_arn}
            
            # Database configuration
            db_name: "production"
            username: "admin"
            password: "${ssm:/production/db/password}"
            port: 5432
            
            # Network configuration
            subnet_group_name: "postgres-subnet-group"
            vpc_security_group_ids: [${dep.securitygroup.outputs.db_security_group_id}]
            
            # Backup configuration
            backup_retention_period: 30
            backup_window: "02:00-03:00"
            maintenance_window: "sun:03:30-sun:04:30"
            
            # High availability
            multi_az: true
            
            # Monitoring
            monitoring_interval: 30
            create_monitoring_role: true
            
            # Parameter group
            parameter_group_name: "postgres14-custom"
            
            # Protection settings
            deletion_protection: true
            skip_final_snapshot: false
            final_snapshot_identifier: "production-db-final-snapshot"
            
            # Tags
            tags:
              Environment: production
              Service: production-database
```

### Aurora PostgreSQL Cluster

```yaml
# Stack configuration (environment.yaml)
components:
  terraform:
    rds/aurora:
      vars:
        region: us-west-2
        
        # Subnet Group
        subnet_groups:
          aurora:
            name: "aurora-subnet-group"
            description: "Subnet group for Aurora cluster"
            subnet_ids: ${dep.vpc.outputs.database_subnet_ids}
        
        # Aurora Cluster
        aurora_clusters:
          analytics:
            cluster_identifier: "analytics-cluster"
            engine: "aurora-postgresql"
            engine_version: "14.7"
            
            # Database configuration
            database_name: "analytics"
            master_username: "admin"
            master_password: "${ssm:/analytics/db/password}"
            port: 5432
            
            # Network configuration
            vpc_security_group_ids: [${dep.securitygroup.outputs.aurora_security_group_id}]
            db_subnet_group_name: "aurora-subnet-group"
            
            # Backup configuration
            backup_retention_period: 14
            preferred_backup_window: "02:00-03:00"
            preferred_maintenance_window: "sun:03:30-sun:04:30"
            
            # Instances configuration
            instances:
              writer:
                identifier: "analytics-writer"
                instance_class: "db.r5.large"
                publicly_accessible: false
              reader1:
                identifier: "analytics-reader-1"
                instance_class: "db.r5.large"
                publicly_accessible: false
              reader2:
                identifier: "analytics-reader-2"
                instance_class: "db.r5.large"
                publicly_accessible: false
            
            # Scaling configuration
            auto_minor_version_upgrade: true
            
            # Encryption
            storage_encrypted: true
            kms_key_id: ${dep.kms.outputs.analytics_key_arn}
            
            # Protection settings
            deletion_protection: true
            skip_final_snapshot: false
            final_snapshot_identifier: "analytics-cluster-final-snapshot"
            
            # Tags
            tags:
              Environment: production
              Service: analytics
```

## Implementation Best Practices

1. **Security**:
   - Store database credentials in AWS Secrets Manager or SSM Parameter Store
   - Enable encryption at rest for all database instances
   - Use security groups to restrict access to database instances
   - Do not expose databases directly to the internet
   - Use IAM authentication when possible
   - Implement regular password rotation

2. **High Availability and Disaster Recovery**:
   - Use Multi-AZ deployments for production databases
   - Set appropriate backup retention periods
   - Test disaster recovery procedures regularly
   - Consider cross-region replicas for critical workloads
   - Enable automated backups
   - Schedule maintenance windows during low-traffic periods

3. **Performance Optimization**:
   - Choose appropriate instance types and sizes for workloads
   - Configure parameter groups to optimize database performance
   - Use enhanced monitoring for production instances
   - Implement appropriate read replicas for read-heavy workloads
   - Consider Aurora for better scaling capabilities
   - Use Provisioned IOPS for I/O-intensive workloads

4. **Cost Optimization**:
   - Rightsize instances based on actual workload
   - Use Aurora Serverless for variable workloads
   - Consider reserved instances for production databases
   - Enable storage autoscaling with reasonable limits
   - Monitor instance performance to avoid overprovisioning
   - Use gp3 storage for better price/performance ratio