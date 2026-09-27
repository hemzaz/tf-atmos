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
    condition     = !var.automatic_failover_enabled || var.cluster_mode_enabled || var.num_cache_nodes >= 2
    error_message = "automatic_failover_enabled requires num_cache_nodes >= 2 (a primary plus at least one replica)."
  }

  validation {
    condition     = !var.cluster_mode_enabled || var.automatic_failover_enabled
    error_message = "Cluster mode requires automatic_failover_enabled."
  }
}

# Cluster mode, named as in Cloud Posse's aws-elasticache-redis component.
variable "cluster_mode_enabled" {
  type        = bool
  description = "Shard the keyspace across node groups (Redis cluster mode). Off: one primary plus num_cache_nodes - 1 replicas. WARNING: changing this value on an existing cache is not an in-place migration in this component (AWS's num_cache_clusters <-> num_node_groups topologies don't convert live through this provider); treat it as a replacement of the cache"
  default     = false
}

variable "cluster_mode_num_node_groups" {
  type        = number
  description = "Number of shards (node groups) in cluster mode"
  default     = 1

  validation {
    condition     = var.cluster_mode_num_node_groups >= 1 && var.cluster_mode_num_node_groups <= 500 && floor(var.cluster_mode_num_node_groups) == var.cluster_mode_num_node_groups
    error_message = "cluster_mode_num_node_groups must be a whole number between 1 and 500."
  }
}

variable "cluster_mode_replicas_per_node_group" {
  type        = number
  description = "Replicas in each shard in cluster mode; 0 is allowed, as AWS does, for cheaper dev/test shards with no failover target"
  default     = 1

  validation {
    condition     = var.cluster_mode_replicas_per_node_group >= 0 && var.cluster_mode_replicas_per_node_group <= 5 && floor(var.cluster_mode_replicas_per_node_group) == var.cluster_mode_replicas_per_node_group
    error_message = "cluster_mode_replicas_per_node_group must be a whole number between 0 and 5."
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
  description = "CIDR blocks allowed to reach the cache port; must be private ranges, never 0.0.0.0/0 or ::/0"
  default     = []

  validation {
    condition     = alltrue([for cidr in var.allowed_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "All entries must be valid IPv4 CIDR blocks."
  }

  # Prefix-length check (not a literal-string check), compared as a number so
  # "/00" (which AWS parses the same as "/0") counts too -- also catches ::/0
  # and any other /0, per components/terraform/eks/variables.tf.
  validation {
    condition     = alltrue([for c in var.allowed_cidr_blocks : try(tonumber(split("/", c)[1]) != 0, true)])
    error_message = "allowed_cidr_blocks must not be open to everywhere (0.0.0.0/0 or any other /0); grant access from explicit private ranges or source security groups."
  }
}

variable "parameter_group_name" {
  type        = string
  description = "Existing cache parameter group to attach. When null, this component creates one if parameters are set or cluster mode is enabled (family is then required), else the engine default is used. WARNING: when cluster_mode_enabled is true, a name given here must itself be a cluster-enabled group (e.g. AWS's default.<family>.cluster.on, or a custom group with cluster-enabled=yes); this is not validated, only documented, because plan-time validation cannot inspect an existing group's parameters"
  default     = null

  validation {
    condition     = var.parameter_group_name == null || length(var.parameters) == 0
    error_message = "Set parameters or an existing parameter_group_name, not both."
  }
}

# family/parameters as in Cloud Posse's aws-elasticache-redis component.
variable "family" {
  type        = string
  description = "Parameter group family (e.g. redis7, valkey8) for the group this component creates. Required with parameters or cluster mode unless parameter_group_name is set"
  default     = null

  validation {
    condition     = var.family == null || can(regex("^(redis|valkey)[0-9]+(\\.[0-9x]+)?$", var.family))
    error_message = "family must be a redis or valkey parameter group family, e.g. redis6.x, redis7, redis5.0 or valkey8."
  }

  validation {
    condition     = var.family != null || var.parameter_group_name != null || (length(var.parameters) == 0 && !var.cluster_mode_enabled)
    error_message = "family is required when parameters are set or cluster mode is on (unless parameter_group_name names an existing group)."
  }

  validation {
    condition     = var.family == null || startswith(var.family, var.engine)
    error_message = "family must match engine: family must start with the engine name, e.g. engine = \"redis\" needs a family like redis6.x/redis7, engine = \"valkey\" needs a family like valkey8."
  }
}

variable "parameters" {
  type = list(object({
    name  = string
    value = string
  }))
  description = "Engine parameters for the group this component creates"
  default     = []

  validation {
    condition     = !anytrue([for p in var.parameters : p.name == "cluster-enabled"])
    error_message = "Do not set cluster-enabled in parameters; use cluster_mode_enabled instead. It is not merged or overridden silently."
  }
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

# auth_token itself is never exported (see outputs.tf); a consumer that needs
# it in-cluster (eks-backend-services) reads it back out of Secrets Manager
# through an ExternalSecret, the same way rds/main's RDS-managed master user
# secret is consumed -- so it must exist as a real secret, not only as a
# Terraform variable that only ever lives in this component's state.
variable "store_auth_token_in_secrets_manager" {
  type        = bool
  description = "Store auth_token in a Secrets Manager secret so it can be read back by an ExternalSecret (e.g. eks-backend-services)"
  default     = true
}

variable "auth_token_secret_kms_key_id" {
  type        = string
  description = "KMS key (ARN, key ID or alias) encrypting the Secrets Manager secret that holds auth_token. null: the AWS-managed aws/secretsmanager key. Set to the same key as kms_key_id to reuse an existing IAM grant scoped to it (e.g. external-secrets' kms_key_arn)"
  default     = null

  validation {
    condition = var.auth_token_secret_kms_key_id == null ? true : can(regex(
      "^(arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:(key|alias)/.+|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|mrk-[0-9a-f]{32}|alias/.+)$",
      var.auth_token_secret_kms_key_id
    ))
    error_message = "auth_token_secret_kms_key_id must be a KMS key ARN, alias ARN, key ID, multi-Region key ID or alias/<name>."
  }
}

variable "auth_token_secret_recovery_window_in_days" {
  type        = number
  description = "Days a deleted auth_token secret stays recoverable: 0 (delete at once) or 7-30, as Cloud Posse's secrets-manager recovery_window_in_days"
  default     = 30

  validation {
    condition     = var.auth_token_secret_recovery_window_in_days == 0 || (var.auth_token_secret_recovery_window_in_days >= 7 && var.auth_token_secret_recovery_window_in_days <= 30)
    error_message = "auth_token_secret_recovery_window_in_days must be 0 or between 7 and 30."
  }
}
