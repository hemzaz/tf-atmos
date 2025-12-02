variable "name_prefix" {
  type        = string
  description = "Prefix for resource naming"
}

variable "environment" {
  type        = string
  description = "Environment name"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID"
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs for subnet group"
}

variable "node_type" {
  type        = string
  description = "Node instance type (e.g., cache.r7g.large)"
  default     = "cache.r7g.large"
}

variable "num_cache_nodes" {
  type        = number
  description = "Number of cache nodes (for non-cluster mode)"
  default     = 2
}

variable "parameter_group_family" {
  type        = string
  description = "Redis parameter group family"
  default     = "redis7"
}

variable "engine_version" {
  type        = string
  description = "Redis engine version"
  default     = "7.0"
}

variable "port" {
  type        = number
  description = "Redis port"
  default     = 6379
}

variable "enable_cluster_mode" {
  type        = bool
  description = "Enable cluster mode (sharding)"
  default     = false
}

variable "num_node_groups" {
  type        = number
  description = "Number of shards (for cluster mode)"
  default     = 1
}

variable "replicas_per_node_group" {
  type        = number
  description = "Replicas per shard (for cluster mode)"
  default     = 1
}

variable "enable_multi_az" {
  type        = bool
  description = "Enable Multi-AZ with automatic failover"
  default     = true
}

variable "enable_automatic_failover" {
  type        = bool
  description = "Enable automatic failover"
  default     = true
}

variable "enable_encryption_at_rest" {
  type        = bool
  description = "Enable encryption at rest"
  default     = true
}

variable "kms_key_id" {
  type        = string
  description = "KMS key ID for encryption"
  default     = null
}

variable "enable_encryption_in_transit" {
  type        = bool
  description = "Enable encryption in transit (TLS)"
  default     = true
}

variable "auth_token" {
  type        = string
  description = "Auth token for Redis AUTH (min 16 chars, requires transit encryption)"
  default     = null
  sensitive   = true
}

variable "snapshot_retention_limit" {
  type        = number
  description = "Backup retention days (0-35)"
  default     = 7
}

variable "snapshot_window" {
  type        = string
  description = "Daily snapshot window (UTC)"
  default     = "03:00-05:00"
}

variable "maintenance_window" {
  type        = string
  description = "Weekly maintenance window"
  default     = "sun:05:00-sun:07:00"
}

variable "enable_auto_minor_version_upgrade" {
  type        = bool
  description = "Enable automatic minor version upgrades"
  default     = false
}

variable "log_delivery_configuration" {
  type = list(object({
    destination      = string
    destination_type = string
    log_format       = string
    log_type         = string
  }))
  description = "CloudWatch log delivery configuration"
  default     = []
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  description = "CIDR blocks allowed to access Redis"
  default     = []
}

variable "allowed_security_group_ids" {
  type        = list(string)
  description = "Security group IDs allowed to access Redis"
  default     = []
}

variable "notification_topic_arn" {
  type        = string
  description = "SNS topic ARN for notifications"
  default     = null
}

variable "apply_immediately" {
  type        = bool
  description = "Apply changes immediately"
  default     = false
}

variable "tags" {
  type        = map(string)
  description = "Additional tags"
  default     = {}
}
