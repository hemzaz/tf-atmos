variable "region" {
  type        = string
  description = "AWS region"
  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-\\d+$", var.region))
    error_message = "The region must be a valid AWS region name (e.g., us-east-1, eu-west-1)."
  }
}

variable "vpc_id" {
  type        = string
  description = "VPC ID where RDS instance will be created"
  validation {
    condition     = can(regex("^vpc-[a-f0-9]+$", var.vpc_id))
    error_message = "VPC ID must be a valid format (e.g., vpc-abc123)."
  }
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR block for security group egress rules"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "Must be a valid IPv4 CIDR block address."
  }
}

variable "additional_egress_rules" {
  type = list(object({
    from_port       = number
    to_port         = number
    protocol        = string
    prefix_list_ids = optional(list(string))
    security_groups = optional(list(string))
    cidr_blocks     = optional(list(string))
    description     = optional(string)
  }))
  description = "List of additional egress rules for the RDS security group"
  default     = []
}

variable "subnet_ids" {
  type        = list(string)
  description = "List of subnet IDs for the DB subnet group"
}

variable "allowed_security_groups" {
  type        = list(string)
  description = "List of security group IDs allowed to connect to the RDS instance"
  default     = []
}

variable "identifier" {
  type        = string
  description = "Identifier for the RDS instance"
}

variable "engine" {
  type        = string
  description = "Database engine type"
  default     = "mysql"
}

variable "engine_version" {
  type        = string
  description = "Database engine version"
  default     = "8.0"
}

variable "family" {
  type        = string
  description = "Database parameter group family"
  default     = "mysql8.0"
}

variable "instance_class" {
  type        = string
  description = "Instance class for the RDS instance"
  default     = "db.t3.small"
}

variable "allocated_storage" {
  type        = number
  description = "Allocated storage size in GB"
  default     = 20
}

variable "max_allocated_storage" {
  type        = number
  description = "Maximum storage size in GB for autoscaling"
  default     = 100
}

variable "storage_type" {
  type        = string
  description = "Storage type for the RDS instance"
  default     = "gp2"
}

variable "storage_encrypted" {
  type        = bool
  description = "Enable storage encryption"
  default     = true
}

variable "kms_key_id" {
  type        = string
  description = "KMS key ID for storage encryption"
  default     = null

  validation {
    condition     = var.kms_key_id == null || var.kms_key_id == "" || can(regex("^arn:aws:kms:[a-z0-9-]+:[0-9]{12}:key/[a-f0-9-]+$", var.kms_key_id))
    error_message = "KMS key ID must be a valid ARN format."
  }
}

variable "username" {
  type        = string
  description = "Username for the database"
  default     = "admin"
}

variable "port" {
  type        = number
  description = "Port for the database"
  default     = 3306
}

variable "db_name" {
  type        = string
  description = "Name of the database"
}

variable "parameters" {
  type = list(object({
    name  = string
    value = string
  }))
  description = "List of DB parameters to set"
  default     = []
}

variable "availability_zone" {
  type        = string
  description = "Availability zone for the RDS instance"
  default     = null
}

variable "multi_az" {
  type        = bool
  description = "Enable Multi-AZ deployment"
  default     = false
}

variable "publicly_accessible" {
  type        = bool
  description = "Make the RDS instance publicly accessible"
  default     = false
}

variable "allow_major_version_upgrade" {
  type        = bool
  description = "Allow major version upgrades"
  default     = false
}

variable "auto_minor_version_upgrade" {
  type        = bool
  description = "Enable automatic minor version upgrades"
  default     = true
}

variable "backup_retention_period" {
  type        = number
  description = "Backup retention period in days"
  default     = 7
}

variable "backup_window" {
  type        = string
  description = "Daily backup window time"
  default     = "03:00-06:00"
}

variable "maintenance_window" {
  type        = string
  description = "Weekly maintenance window time"
  default     = "Sun:00:00-Sun:03:00"
}

variable "skip_final_snapshot" {
  type        = bool
  description = "Skip final snapshot when deleting the RDS instance"
  default     = false
}

variable "copy_tags_to_snapshot" {
  type        = bool
  description = "Copy tags to backups and snapshots"
  default     = true
}

variable "monitoring_interval" {
  type        = number
  description = "Enhanced monitoring interval in seconds (0 to disable)"
  default     = 60

  validation {
    condition     = contains([0, 1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "Monitoring interval must be one of: 0, 1, 5, 10, 15, 30, 60."
  }
}

variable "monitoring_role_arn" {
  type        = string
  description = "ARN of the IAM role for enhanced monitoring"
  default     = null
}

variable "create_monitoring_role" {
  type        = bool
  description = "Create an IAM role for RDS enhanced monitoring"
  default     = true
}

variable "performance_insights_enabled" {
  type        = bool
  description = "Enable Performance Insights"
  default     = true
}

variable "deletion_protection" {
  type        = bool
  description = "Enable deletion protection"
  default     = true
}

variable "prevent_destroy" {
  type        = bool
  description = "Prevent destroy of the RDS instance through the lifecycle"
  default     = true
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to resources"
  default     = {}
}

# Performance Optimization Variables
variable "create_read_replica" {
  type        = bool
  description = "Create a read replica for performance scaling"
  default     = false
}

variable "read_replica_instance_class" {
  type        = string
  description = "Instance class for the read replica (defaults to main instance class)"
  default     = null
}

variable "performance_insights_retention_period" {
  type        = number
  description = "Performance Insights retention period in days"
  default     = 7
  validation {
    condition     = contains([7, 731], var.performance_insights_retention_period)
    error_message = "Performance Insights retention period must be either 7 or 731 days."
  }
}

variable "enabled_cloudwatch_logs_exports" {
  type        = list(string)
  description = "List of log types to export to CloudWatch"
  default     = []
}

variable "iops" {
  type        = number
  description = "The amount of provisioned IOPS"
  default     = null
}

variable "storage_throughput" {
  type        = number
  description = "Storage throughput value for gp3 storage type"
  default     = null
}

# Database Performance Parameters
variable "max_connections" {
  type        = number
  description = "Maximum number of connections to the database"
  default     = 100
}

variable "work_mem_mb" {
  type        = number
  description = "Amount of memory used for internal sort operations and hash tables (PostgreSQL)"
  default     = 4
}

variable "maintenance_work_mem_mb" {
  type        = number
  description = "Amount of memory used for maintenance operations (PostgreSQL)"
  default     = 64
}

variable "effective_cache_size_mb" {
  type        = number
  description = "Effective cache size for query planning (PostgreSQL)"
  default     = 128
}

variable "random_page_cost" {
  type        = number
  description = "Random page cost for query planning (PostgreSQL)"
  default     = 1.1
}

variable "checkpoint_completion_target" {
  type        = number
  description = "Checkpoint completion target (PostgreSQL)"
  default     = 0.9
  validation {
    condition     = var.checkpoint_completion_target >= 0.0 && var.checkpoint_completion_target <= 1.0
    error_message = "Checkpoint completion target must be between 0.0 and 1.0."
  }
}

# RDS Proxy Configuration
variable "enable_rds_proxy" {
  type        = bool
  description = "Enable RDS Proxy for connection pooling"
  default     = false
}

variable "proxy_require_tls" {
  type        = bool
  description = "Require TLS for RDS Proxy connections"
  default     = true
}

variable "proxy_idle_client_timeout" {
  type        = number
  description = "Idle client timeout in seconds for RDS Proxy"
  default     = 1800
}

variable "proxy_max_connections_percent" {
  type        = number
  description = "Maximum connections as percentage of max_connections for RDS Proxy"
  default     = 100
  validation {
    condition     = var.proxy_max_connections_percent >= 1 && var.proxy_max_connections_percent <= 100
    error_message = "Proxy max connections percent must be between 1 and 100."
  }
}

variable "proxy_max_idle_connections_percent" {
  type        = number
  description = "Maximum idle connections as percentage of max_connections for RDS Proxy"
  default     = 50
  validation {
    condition     = var.proxy_max_idle_connections_percent >= 0 && var.proxy_max_idle_connections_percent <= 100
    error_message = "Proxy max idle connections percent must be between 0 and 100."
  }
}

# Enhanced Security Variables
variable "custom_ingress_rules" {
  type = list(object({
    description     = string
    from_port       = number
    to_port         = number
    protocol        = string
    cidr_blocks     = optional(list(string))
    security_groups = optional(list(string))
  }))
  description = "Custom ingress rules for RDS security group"
  default     = []
}

# Performance Monitoring Variables
variable "create_performance_alarms" {
  type        = bool
  description = "Create CloudWatch alarms for database performance monitoring"
  default     = false
}

variable "cpu_alarm_threshold" {
  type        = number
  description = "CPU utilization alarm threshold percentage"
  default     = 80
  validation {
    condition     = var.cpu_alarm_threshold >= 0 && var.cpu_alarm_threshold <= 100
    error_message = "CPU alarm threshold must be between 0 and 100."
  }
}

variable "connection_alarm_threshold" {
  type        = number
  description = "Database connection count alarm threshold"
  default     = 80
}

variable "free_storage_alarm_threshold" {
  type        = number
  description = "Free storage space alarm threshold in bytes"
  default     = 2147483648 # 2GB in bytes
}

variable "sns_topic_arn" {
  type        = string
  description = "SNS topic ARN for sending alarm notifications"
  default     = null
}