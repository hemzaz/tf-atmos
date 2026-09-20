variable "region" {
  type        = string
  description = "AWS region"
  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-\\d+$", var.region))
    error_message = "The region must be a valid AWS region name (e.g., us-east-1, eu-west-1)."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to resources; must include Environment (used in resource names)"

  validation {
    condition     = trimspace(lookup(var.tags, "Environment", "")) != ""
    error_message = "tags must include a non-empty Environment value."
  }
}

variable "enabled" {
  type        = bool
  description = "Set to false to prevent the component from creating any resources"
  default     = true
}

variable "cluster_id" {
  type        = string
  description = "Name of the cache, used as the replication group ID suffix"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,28}[a-z0-9]$", var.cluster_id))
    error_message = "cluster_id must be 2-30 lowercase alphanumeric characters or hyphens, starting with a letter and not ending in a hyphen."
  }
}

variable "vpc_id" {
  type        = string
  description = "VPC ID where the cache security group will be created"
  validation {
    condition     = can(regex("^vpc-[a-f0-9]+$", var.vpc_id))
    error_message = "VPC ID must be a valid format (e.g., vpc-abc123)."
  }
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs for the cache subnet group; use private subnets in at least two AZs"

  validation {
    condition     = length(var.subnet_ids) > 0
    error_message = "At least one subnet ID must be provided."
  }
}

variable "engine" {
  type        = string
  description = "Cache engine"
  default     = "redis"

  validation {
    condition     = contains(["redis", "valkey"], var.engine)
    error_message = "engine must be redis or valkey; memcached has no replication group."
  }
}

variable "engine_version" {
  type        = string
  description = "Cache engine version"
  default     = "7.0"
}

variable "node_type" {
  type        = string
  description = "Instance class for each cache node"
  default     = "cache.t4g.micro"

  validation {
    condition     = can(regex("^cache\\.[a-z0-9]+\\.[a-z0-9]+$", var.node_type))
    error_message = "node_type must be a valid ElastiCache node type (e.g., cache.r5.large)."
  }
}

variable "num_cache_nodes" {
  type        = number
  description = "Number of nodes in the replication group (1 primary + N-1 replicas); maps to num_cache_clusters"
  default     = 2

  validation {
    condition     = var.num_cache_nodes >= 1 && var.num_cache_nodes <= 6 && floor(var.num_cache_nodes) == var.num_cache_nodes
    error_message = "num_cache_nodes must be a whole number between 1 and 6."
  }
}

variable "automatic_failover_enabled" {
  type        = bool
  description = "Promote a replica to primary when the primary fails; requires at least 2 nodes"
  default     = true

  validation {
    condition     = !var.automatic_failover_enabled || var.num_cache_nodes >= 2
    error_message = "automatic_failover_enabled requires num_cache_nodes >= 2 (a primary plus at least one replica)."
  }
}

variable "multi_az_enabled" {
  type        = bool
  description = "Spread nodes across Availability Zones; requires automatic failover"
  default     = true

  validation {
    condition     = !var.multi_az_enabled || var.automatic_failover_enabled
    error_message = "multi_az_enabled requires automatic_failover_enabled."
  }
}

variable "at_rest_encryption_enabled" {
  type        = bool
  description = "Encrypt data at rest (always required)"
  default     = true

  validation {
    condition     = var.at_rest_encryption_enabled
    error_message = "At-rest encryption must be enabled for all caches for security compliance."
  }
}

variable "transit_encryption_enabled" {
  type        = bool
  description = "Encrypt data in transit (always required)"
  default     = true

  validation {
    condition     = var.transit_encryption_enabled
    error_message = "In-transit encryption must be enabled for all caches for security compliance."
  }
}

variable "auth_token" {
  type        = string
  description = "Redis AUTH token; required when transit encryption is enabled. Supply from a secret store, never in plain YAML"
  default     = null
  sensitive   = true

  validation {
    condition     = !var.transit_encryption_enabled || var.auth_token != null
    error_message = "auth_token is required when transit_encryption_enabled is true."
  }

  validation {
    condition     = var.auth_token == null || can(regex("^[^/\"@ ]{16,128}$", var.auth_token))
    error_message = "auth_token must be 16-128 characters and must not contain '/', '\"', '@' or spaces."
  }
}

variable "kms_key_id" {
  type        = string
  description = "Customer-managed KMS key ARN for at-rest encryption; AWS-owned key when null"
  default     = null

  validation {
    condition     = var.kms_key_id == null || can(regex("^arn:aws:kms:[a-z0-9-]+:[0-9]{12}:key/[a-f0-9-]+$", var.kms_key_id))
    error_message = "kms_key_id must be a valid KMS key ARN."
  }
}

variable "port" {
  type        = number
  description = "Port the cache listens on"
  default     = 6379

  validation {
    condition     = var.port > 0 && var.port <= 65535
    error_message = "port must be between 1 and 65535."
  }
}

variable "allowed_security_group_ids" {
  type        = list(string)
  description = "Security group IDs allowed to reach the cache port"
  default     = []

  validation {
    condition     = alltrue([for sg in var.allowed_security_group_ids : can(regex("^sg-[a-f0-9]+$", sg))])
    error_message = "Each entry must be a valid security group ID (e.g., sg-abc123)."
  }
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  description = "CIDR blocks allowed to reach the cache port; must be private ranges, never 0.0.0.0/0"
  default     = []

  validation {
    condition     = alltrue([for cidr in var.allowed_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "All entries must be valid IPv4 CIDR blocks."
  }

  validation {
    condition     = !contains(var.allowed_cidr_blocks, "0.0.0.0/0")
    error_message = "allowed_cidr_blocks must not contain 0.0.0.0/0; grant access from explicit private ranges or source security groups."
  }
}

variable "parameter_group_name" {
  type        = string
  description = "Existing cache parameter group to attach; the engine default is used when null"
  default     = null
}

variable "snapshot_retention_limit" {
  type        = number
  description = "Days to retain automatic snapshots; backups cannot be turned off"
  default     = 7

  validation {
    condition     = var.snapshot_retention_limit >= 1 && var.snapshot_retention_limit <= 35
    error_message = "snapshot_retention_limit must be between 1 and 35; backups cannot be disabled."
  }
}

variable "snapshot_window" {
  type        = string
  description = "Daily UTC window for automatic snapshots (hh:mm-hh:mm)"
  default     = "03:00-05:00"

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]-([01][0-9]|2[0-3]):[0-5][0-9]$", var.snapshot_window))
    error_message = "snapshot_window must look like 03:00-05:00."
  }
}

variable "maintenance_window" {
  type        = string
  description = "Weekly UTC maintenance window (ddd:hh:mm-ddd:hh:mm)"
  default     = "sun:05:00-sun:07:00"

  validation {
    condition     = can(regex("^(mon|tue|wed|thu|fri|sat|sun):([01][0-9]|2[0-3]):[0-5][0-9]-(mon|tue|wed|thu|fri|sat|sun):([01][0-9]|2[0-3]):[0-5][0-9]$", var.maintenance_window))
    error_message = "maintenance_window must look like sun:05:00-sun:07:00 with lowercase day names."
  }
}

variable "auto_minor_version_upgrade" {
  type        = bool
  description = "Apply minor engine version upgrades automatically during the maintenance window"
  default     = true
}

variable "apply_immediately" {
  type        = bool
  description = "Apply modifications immediately instead of during the maintenance window"
  default     = false
}
