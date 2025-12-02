#------------------------------------------------------------------------------
# Required Variables
#------------------------------------------------------------------------------

variable "name_prefix" {
  type        = string
  description = <<-EOT
    Prefix for resource naming. Will be used to construct names like:
    {name_prefix}-{environment}-aurora-cluster
    Example: "myapp-prod-aurora-cluster"
  EOT

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.name_prefix))
    error_message = "name_prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  type        = string
  description = <<-EOT
    Environment name (e.g., dev, staging, prod). Used for resource naming and tagging.
    Example: "production"
  EOT

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "vpc_id" {
  type        = string
  description = <<-EOT
    The VPC ID where the Aurora cluster will be deployed.
    Example: "vpc-0123456789abcdef0"
  EOT

  validation {
    condition     = can(regex("^vpc-", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID starting with 'vpc-'."
  }
}

variable "subnet_ids" {
  type        = list(string)
  description = <<-EOT
    List of subnet IDs for the DB subnet group. Should be in multiple availability zones
    for high availability. Typically use database/private subnets, not public subnets.
    Example: ["subnet-abc123", "subnet-def456", "subnet-ghi789"]
  EOT

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "At least 2 subnet IDs are required for multi-AZ deployment."
  }

  validation {
    condition     = alltrue([for s in var.subnet_ids : can(regex("^subnet-", s))])
    error_message = "All subnet IDs must be valid and start with 'subnet-'."
  }
}

#------------------------------------------------------------------------------
# Engine Configuration
#------------------------------------------------------------------------------

variable "engine" {
  type        = string
  description = <<-EOT
    Aurora database engine type. Options:
    - "aurora-postgresql" for PostgreSQL-compatible
    - "aurora-mysql" for MySQL-compatible
    Default: "aurora-postgresql"
  EOT
  default     = "aurora-postgresql"

  validation {
    condition     = contains(["aurora-postgresql", "aurora-mysql"], var.engine)
    error_message = "engine must be either 'aurora-postgresql' or 'aurora-mysql'."
  }
}

variable "engine_version" {
  type        = string
  description = <<-EOT
    Database engine version. Use specific version for production.
    Examples:
    - PostgreSQL: "15.4", "14.9", "13.12"
    - MySQL: "8.0.mysql_aurora.3.04.0"
    Leave empty for latest version (not recommended for production).
  EOT
  default     = null
}

variable "engine_mode" {
  type        = string
  description = <<-EOT
    Aurora engine mode:
    - "provisioned" for traditional Aurora instances
    - "serverless" for Aurora Serverless v1 (deprecated, use serverlessv2_scaling_configuration)
    Default: "provisioned"
  EOT
  default     = "provisioned"

  validation {
    condition     = contains(["provisioned", "serverless"], var.engine_mode)
    error_message = "engine_mode must be either 'provisioned' or 'serverless'."
  }
}

variable "enable_serverlessv2" {
  type        = bool
  description = <<-EOT
    Enable Aurora Serverless v2 for auto-scaling capacity. When true, creates instances
    with 'db.serverless' class and uses serverlessv2_scaling_configuration for scaling.
    Default: false
  EOT
  default     = false
}

variable "serverlessv2_min_capacity" {
  type        = number
  description = <<-EOT
    Minimum Aurora Capacity Units (ACUs) for Serverless v2. Each ACU is 2GB RAM + compute.
    Range: 0.5 to 128 ACUs. Default: 0.5 (1GB RAM).
  EOT
  default     = 0.5

  validation {
    condition     = var.serverlessv2_min_capacity >= 0.5 && var.serverlessv2_min_capacity <= 128
    error_message = "serverlessv2_min_capacity must be between 0.5 and 128."
  }
}

variable "serverlessv2_max_capacity" {
  type        = number
  description = <<-EOT
    Maximum Aurora Capacity Units (ACUs) for Serverless v2. Each ACU is 2GB RAM + compute.
    Range: 0.5 to 128 ACUs. Must be >= min_capacity. Default: 16 (32GB RAM).
  EOT
  default     = 16

  validation {
    condition     = var.serverlessv2_max_capacity >= 0.5 && var.serverlessv2_max_capacity <= 128
    error_message = "serverlessv2_max_capacity must be between 0.5 and 128."
  }
}

#------------------------------------------------------------------------------
# Instance Configuration
#------------------------------------------------------------------------------

variable "instance_class" {
  type        = string
  description = <<-EOT
    Instance class for Aurora cluster instances. Use 'db.serverless' for Serverless v2.
    Common classes:
    - db.r6g.large (2 vCPU, 16GB RAM) - recommended for production
    - db.r6g.xlarge (4 vCPU, 32GB RAM)
    - db.r6g.2xlarge (8 vCPU, 64GB RAM)
    - db.t4g.medium (2 vCPU, 4GB RAM) - for dev/test
    - db.serverless - for Serverless v2
    Default: "db.r6g.large"
  EOT
  default     = "db.r6g.large"
}

variable "instance_count" {
  type        = number
  description = <<-EOT
    Number of Aurora instances to create. For high availability, use at least 2.
    Each additional instance is a read replica and provides failover capability.
    Default: 2 (one writer, one reader)
  EOT
  default     = 2

  validation {
    condition     = var.instance_count >= 1 && var.instance_count <= 15
    error_message = "instance_count must be between 1 and 15."
  }
}

variable "enable_autoscaling" {
  type        = bool
  description = <<-EOT
    Enable auto-scaling for Aurora read replicas. Creates additional read replicas
    based on CPU utilization. Only applicable when instance_count > 1.
    Default: true
  EOT
  default     = true
}

variable "autoscaling_min_capacity" {
  type        = number
  description = <<-EOT
    Minimum number of read replicas for auto-scaling. Must be >= 1 and < instance_count.
    Default: 1
  EOT
  default     = 1

  validation {
    condition     = var.autoscaling_min_capacity >= 1 && var.autoscaling_min_capacity <= 15
    error_message = "autoscaling_min_capacity must be between 1 and 15."
  }
}

variable "autoscaling_max_capacity" {
  type        = number
  description = <<-EOT
    Maximum number of read replicas for auto-scaling. Should be > instance_count
    to allow scaling up during high load.
    Default: 5
  EOT
  default     = 5

  validation {
    condition     = var.autoscaling_max_capacity >= 1 && var.autoscaling_max_capacity <= 15
    error_message = "autoscaling_max_capacity must be between 1 and 15."
  }
}

variable "autoscaling_target_cpu" {
  type        = number
  description = <<-EOT
    Target CPU utilization percentage for auto-scaling. When average CPU exceeds this
    threshold, new read replicas are added. Range: 20-90%.
    Default: 70 (scale when CPU > 70%)
  EOT
  default     = 70

  validation {
    condition     = var.autoscaling_target_cpu >= 20 && var.autoscaling_target_cpu <= 90
    error_message = "autoscaling_target_cpu must be between 20 and 90."
  }
}

variable "autoscaling_target_connections" {
  type        = number
  description = <<-EOT
    Target connection count percentage for auto-scaling. When average connections exceed
    this percentage of max_connections, new read replicas are added. Range: 40-90%.
    Default: 80 (scale when connections > 80% of max)
  EOT
  default     = 80

  validation {
    condition     = var.autoscaling_target_connections >= 40 && var.autoscaling_target_connections <= 90
    error_message = "autoscaling_target_connections must be between 40 and 90."
  }
}

#------------------------------------------------------------------------------
# Database Configuration
#------------------------------------------------------------------------------

variable "database_name" {
  type        = string
  description = <<-EOT
    Name of the initial database to create. Leave empty to skip initial database creation.
    Will be created on cluster creation. Must start with a letter.
    Example: "myapp" will create database "myapp"
  EOT
  default     = null

  validation {
    condition     = var.database_name == null || can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", var.database_name))
    error_message = "database_name must start with a letter and contain only alphanumeric characters and underscores."
  }
}

variable "master_username" {
  type        = string
  description = <<-EOT
    Master username for the database. Cannot be 'admin' or other reserved words.
    Default: "dbadmin"
  EOT
  default     = "dbadmin"

  validation {
    condition     = !contains(["admin", "root", "postgres", "mysql"], var.master_username)
    error_message = "master_username cannot be a reserved word like 'admin', 'root', 'postgres', or 'mysql'."
  }
}

variable "master_password_secret_arn" {
  type        = string
  description = <<-EOT
    ARN of AWS Secrets Manager secret containing the master password.
    Secret must contain a JSON with 'password' key or be a plain string.
    Example: "arn:aws:secretsmanager:us-east-1:123456789012:secret:db-password-abc123"
    If not provided, a random password will be generated and stored in Secrets Manager.
  EOT
  default     = null
}

variable "enable_secrets_rotation" {
  type        = bool
  description = <<-EOT
    Enable automatic rotation of database master password using Lambda.
    Requires master_password_secret_arn or will use the generated secret.
    Rotation occurs every 30 days by default.
    Default: true
  EOT
  default     = true
}

variable "secrets_rotation_days" {
  type        = number
  description = <<-EOT
    Number of days between automatic secret rotations. Range: 1-365 days.
    Default: 30 days
  EOT
  default     = 30

  validation {
    condition     = var.secrets_rotation_days >= 1 && var.secrets_rotation_days <= 365
    error_message = "secrets_rotation_days must be between 1 and 365."
  }
}

variable "port" {
  type        = number
  description = <<-EOT
    Database port number.
    Default: 5432 for PostgreSQL, 3306 for MySQL (automatically set based on engine)
  EOT
  default     = null
}

#------------------------------------------------------------------------------
# High Availability Configuration
#------------------------------------------------------------------------------

variable "enable_multi_az" {
  type        = bool
  description = <<-EOT
    Enable Multi-AZ deployment. When true, Aurora automatically creates read replicas
    in different availability zones for high availability and failover.
    Default: true (recommended for production)
  EOT
  default     = true
}

variable "preferred_backup_window" {
  type        = string
  description = <<-EOT
    Daily time range for automated backups (UTC). Format: "HH:MM-HH:MM".
    Must be at least 30 minutes and not overlap with preferred_maintenance_window.
    Example: "03:00-04:00" (3 AM to 4 AM UTC)
    Default: "03:00-04:00"
  EOT
  default     = "03:00-04:00"

  validation {
    condition     = can(regex("^([01]?[0-9]|2[0-3]):[0-5][0-9]-([01]?[0-9]|2[0-3]):[0-5][0-9]$", var.preferred_backup_window))
    error_message = "preferred_backup_window must be in format HH:MM-HH:MM."
  }
}

variable "preferred_maintenance_window" {
  type        = string
  description = <<-EOT
    Weekly time range for maintenance (UTC). Format: "ddd:HH:MM-ddd:HH:MM".
    Days: mon, tue, wed, thu, fri, sat, sun
    Must not overlap with preferred_backup_window.
    Example: "sun:04:00-sun:05:00" (Sunday 4-5 AM UTC)
    Default: "sun:04:00-sun:05:00"
  EOT
  default     = "sun:04:00-sun:05:00"

  validation {
    condition     = can(regex("^(mon|tue|wed|thu|fri|sat|sun):[0-2][0-9]:[0-5][0-9]-(mon|tue|wed|thu|fri|sat|sun):[0-2][0-9]:[0-5][0-9]$", var.preferred_maintenance_window))
    error_message = "preferred_maintenance_window must be in format ddd:HH:MM-ddd:HH:MM."
  }
}

#------------------------------------------------------------------------------
# Backup Configuration
#------------------------------------------------------------------------------

variable "backup_retention_period" {
  type        = number
  description = <<-EOT
    Number of days to retain automated backups. Range: 1-35 days.
    For compliance, consider 7-35 days. Set to 1 for dev environments.
    Default: 7 days
  EOT
  default     = 7

  validation {
    condition     = var.backup_retention_period >= 1 && var.backup_retention_period <= 35
    error_message = "backup_retention_period must be between 1 and 35 days."
  }
}

variable "copy_tags_to_snapshot" {
  type        = bool
  description = <<-EOT
    Copy all cluster tags to automated and manual snapshots.
    Useful for cost tracking and compliance.
    Default: true
  EOT
  default     = true
}

variable "enable_final_snapshot" {
  type        = bool
  description = <<-EOT
    Create a final snapshot when the cluster is deleted. Highly recommended for production.
    Snapshot will be named: {cluster_identifier}-final-{timestamp}
    Default: true
  EOT
  default     = true
}

variable "skip_final_snapshot" {
  type        = bool
  description = <<-EOT
    Skip the final snapshot when deleting the cluster. Only set to true for dev/test.
    Default: false (create final snapshot)
  EOT
  default     = false
}

variable "snapshot_identifier" {
  type        = string
  description = <<-EOT
    Snapshot ID to restore from. If provided, creates cluster from this snapshot.
    Example: "myapp-prod-final-2024-12-01"
  EOT
  default     = null
}

#------------------------------------------------------------------------------
# Performance Insights
#------------------------------------------------------------------------------

variable "enable_performance_insights" {
  type        = bool
  description = <<-EOT
    Enable Performance Insights for advanced database monitoring and performance tuning.
    Provides detailed visibility into database load and query performance.
    Additional cost: ~$0.09/vCPU/day
    Default: true (recommended for production)
  EOT
  default     = true
}

variable "performance_insights_retention_period" {
  type        = number
  description = <<-EOT
    Performance Insights data retention period in days.
    Options: 7 (free), 31, 62, 93, 124, 155, 186, 217, 248, 279, 310, 341, 372, 403, 434, 465, 496, 527, 558, 589, 620, 651, 682, 713, 731
    Default: 7 days (free tier)
  EOT
  default     = 7

  validation {
    condition     = contains([7, 31, 62, 93, 124, 155, 186, 217, 248, 279, 310, 341, 372, 403, 434, 465, 496, 527, 558, 589, 620, 651, 682, 713, 731], var.performance_insights_retention_period)
    error_message = "performance_insights_retention_period must be 7 or a valid extended retention value."
  }
}

variable "performance_insights_kms_key_id" {
  type        = string
  description = <<-EOT
    KMS key ID for encrypting Performance Insights data.
    If not specified, uses the default AWS managed key.
    Example: "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
  EOT
  default     = null
}

#------------------------------------------------------------------------------
# Enhanced Monitoring
#------------------------------------------------------------------------------

variable "enable_enhanced_monitoring" {
  type        = bool
  description = <<-EOT
    Enable Enhanced Monitoring for real-time operating system metrics.
    Provides CPU, memory, file system, and disk I/O metrics at 1-60 second intervals.
    Additional cost: ~$1.50/instance/month for 10-second granularity.
    Default: true (recommended for production)
  EOT
  default     = true
}

variable "monitoring_interval" {
  type        = number
  description = <<-EOT
    Enhanced monitoring interval in seconds. Valid values: 0 (disabled), 1, 5, 10, 15, 30, 60.
    Lower intervals provide more granular data but cost more.
    Default: 10 seconds
  EOT
  default     = 10

  validation {
    condition     = contains([0, 1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "monitoring_interval must be one of: 0, 1, 5, 10, 15, 30, 60."
  }
}

variable "monitoring_role_arn" {
  type        = string
  description = <<-EOT
    IAM role ARN for Enhanced Monitoring. If not provided, one will be created automatically.
    Example: "arn:aws:iam::123456789012:role/rds-monitoring-role"
  EOT
  default     = null
}

#------------------------------------------------------------------------------
# Security Configuration
#------------------------------------------------------------------------------

variable "kms_key_id" {
  type        = string
  description = <<-EOT
    KMS key ID or ARN for encrypting database storage.
    If not specified, uses the default AWS RDS managed key.
    Example: "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
  EOT
  default     = null
}

variable "storage_encrypted" {
  type        = bool
  description = <<-EOT
    Enable encryption at rest for database storage using KMS.
    Required for compliance workloads (HIPAA, PCI-DSS, etc.).
    Default: true (strongly recommended)
  EOT
  default     = true
}

variable "enable_cloudwatch_logs_exports" {
  type        = list(string)
  description = <<-EOT
    List of log types to export to CloudWatch Logs.
    PostgreSQL: ["postgresql"]
    MySQL: ["audit", "error", "general", "slowquery"]
    Default: all available logs for the engine
  EOT
  default     = null
}

variable "security_group_ids" {
  type        = list(string)
  description = <<-EOT
    List of security group IDs to attach to the cluster.
    If not provided, a default security group will be created.
    Example: ["sg-abc123", "sg-def456"]
  EOT
  default     = []
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  description = <<-EOT
    List of CIDR blocks allowed to access the database (if creating default security group).
    Use private subnet CIDRs, never use 0.0.0.0/0 in production.
    Example: ["10.0.10.0/24", "10.0.11.0/24"]
  EOT
  default     = []
}

variable "allowed_security_group_ids" {
  type        = list(string)
  description = <<-EOT
    List of security group IDs allowed to access the database (if creating default security group).
    Example: ["sg-app-servers", "sg-lambda-functions"]
  EOT
  default     = []
}

variable "enable_deletion_protection" {
  type        = bool
  description = <<-EOT
    Enable deletion protection to prevent accidental cluster deletion.
    Must be disabled before cluster can be deleted.
    Default: true (strongly recommended for production)
  EOT
  default     = true
}

variable "enable_iam_database_authentication" {
  type        = bool
  description = <<-EOT
    Enable IAM database authentication for password-free database access using IAM roles.
    More secure than passwords for applications.
    Default: true
  EOT
  default     = true
}

#------------------------------------------------------------------------------
# Parameter Groups
#------------------------------------------------------------------------------

variable "cluster_parameter_group_name" {
  type        = string
  description = <<-EOT
    Name of existing cluster parameter group to use.
    If not provided, a new parameter group will be created with optimized settings.
  EOT
  default     = null
}

variable "cluster_parameters" {
  type = list(object({
    name         = string
    value        = string
    apply_method = optional(string, "immediate")
  }))
  description = <<-EOT
    List of cluster parameters to apply. Used when creating a new parameter group.
    Example:
    [
      {
        name  = "shared_preload_libraries"
        value = "pg_stat_statements,auto_explain"
        apply_method = "pending-reboot"
      },
      {
        name  = "log_min_duration_statement"
        value = "1000"  # Log queries taking > 1 second
      }
    ]
  EOT
  default     = []
}

variable "db_parameter_group_name" {
  type        = string
  description = <<-EOT
    Name of existing DB parameter group to use for instances.
    If not provided, a new parameter group will be created with optimized settings.
  EOT
  default     = null
}

variable "db_parameters" {
  type = list(object({
    name         = string
    value        = string
    apply_method = optional(string, "immediate")
  }))
  description = <<-EOT
    List of DB instance parameters to apply. Used when creating a new parameter group.
  EOT
  default     = []
}

#------------------------------------------------------------------------------
# Global Cluster (Cross-Region)
#------------------------------------------------------------------------------

variable "enable_global_cluster" {
  type        = bool
  description = <<-EOT
    Enable Aurora Global Database for cross-region replication and disaster recovery.
    Allows read replicas in multiple regions with < 1 second replication lag.
    Additional cost applies.
    Default: false
  EOT
  default     = false
}

variable "global_cluster_identifier" {
  type        = string
  description = <<-EOT
    Identifier for the Aurora global database cluster.
    Required when enable_global_cluster is true.
    Example: "myapp-global"
  EOT
  default     = null
}

variable "is_primary_cluster" {
  type        = bool
  description = <<-EOT
    Whether this is the primary cluster in a global database.
    Set to true for the primary region, false for secondary regions.
    Default: true
  EOT
  default     = true
}

#------------------------------------------------------------------------------
# Cost Optimization
#------------------------------------------------------------------------------

variable "auto_minor_version_upgrade" {
  type        = bool
  description = <<-EOT
    Enable automatic minor version upgrades during maintenance windows.
    Recommended for dev/staging, consider false for production to control upgrades.
    Default: false (manual control for production)
  EOT
  default     = false
}

variable "apply_immediately" {
  type        = bool
  description = <<-EOT
    Apply database modifications immediately instead of during next maintenance window.
    May cause downtime for some changes. Use false for production.
    Default: false
  EOT
  default     = false
}

variable "deletion_protection" {
  type        = bool
  description = <<-EOT
    Protect the cluster from deletion. Must be disabled to delete cluster.
    Alias for enable_deletion_protection for backwards compatibility.
    Default: true
  EOT
  default     = true
}

#------------------------------------------------------------------------------
# Tags
#------------------------------------------------------------------------------

variable "tags" {
  type        = map(string)
  description = <<-EOT
    Additional tags to apply to all resources.
    Example:
    {
      Team        = "platform"
      CostCenter  = "engineering"
      Compliance  = "pci-dss"
    }
  EOT
  default     = {}
}
