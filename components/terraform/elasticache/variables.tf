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

variable "auth_token_version" {
  type        = number
  description = "Version of the write-only AUTH token generated by this component. Terraform sends a new token to the replication group and its secret only when this changes: increment it to rotate. The ROTATE update strategy keeps the previous token valid alongside the new one, so clients can switch over"
  default     = 1

  validation {
    condition     = var.auth_token_version >= 1 && floor(var.auth_token_version) == var.auth_token_version
    error_message = "auth_token_version must be a positive integer."
  }
}

# The generated token exists only in this secret (outputs, plan and state
# never hold it), so turn this off only when something else takes the token
# over at once, e.g. a rotation Lambda whose first rotation SETs its own
# token (the microservices-platform template).
variable "store_auth_token_in_secrets_manager" {
  type        = bool
  description = "Store the generated AUTH token in the redis-auth/<Environment>/<cluster_id> Secrets Manager secret, read back by an ExternalSecret (e.g. eks-backend-services). false: the token is set on the cache and kept nowhere"
  default     = true
}

variable "log_delivery_configuration" {
  type = list(object({
    log_type   = string
    log_format = optional(string, "text")
  }))
  description = "Logs the cache delivers to CloudWatch Logs, one entry per log_type (slow-log, engine-log). Each gets a log group, /aws/elasticache/<Environment>-<cluster_id>/<log_type>, encrypted with log_kms_key_id. Cloud Posse aws-elasticache-redis's input, minus the destination this component creates"
  default     = []
  nullable    = false

  validation {
    condition = alltrue([
      for entry in var.log_delivery_configuration :
      contains(["slow-log", "engine-log"], entry.log_type) && contains(["text", "json"], entry.log_format)
    ])
    error_message = "log_delivery_configuration entries need log_type slow-log or engine-log and log_format text or json."
  }

  validation {
    condition     = length(distinct([for entry in var.log_delivery_configuration : entry.log_type])) == length(var.log_delivery_configuration)
    error_message = "log_delivery_configuration may list each log_type once."
  }

  validation {
    condition     = length(var.log_delivery_configuration) == 0 || var.log_kms_key_id != null
    error_message = "log_delivery_configuration needs log_kms_key_id: the log groups are always encrypted with a customer managed key."
  }
}

variable "log_retention_in_days" {
  type        = number
  description = "Retention of the log_delivery_configuration log groups, in days"
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_in_days)
    error_message = "log_retention_in_days must be a CloudWatch Logs retention period."
  }
}

variable "log_kms_key_id" {
  type        = string
  description = "Customer managed KMS key ARN encrypting the log_delivery_configuration log groups (kms/main's key_arn; its policy must allow logs.<region>.amazonaws.com)"
  default     = null

  validation {
    condition     = var.log_kms_key_id == null || can(regex("^arn:aws:kms:[a-z0-9-]+:[0-9]{12}:key/[a-f0-9-]+$", var.log_kms_key_id))
    error_message = "log_kms_key_id must be a valid KMS key ARN."
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

variable "auth_token_secret_kms_key_id" {
  type        = string
  description = "KMS key (ARN, key ID or alias) encrypting the Secrets Manager secret that holds the generated AUTH token. null: the AWS-managed aws/secretsmanager key. Set to the same key as kms_key_id to reuse an existing IAM grant scoped to it (e.g. external-secrets' kms_key_arn)"
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
  description = "Days a deleted AUTH token secret stays recoverable: 0 (delete at once) or 7-30, as Cloud Posse's secrets-manager recovery_window_in_days"
  default     = 30

  validation {
    condition     = var.auth_token_secret_recovery_window_in_days == 0 || (var.auth_token_secret_recovery_window_in_days >= 7 && var.auth_token_secret_recovery_window_in_days <= 30)
    error_message = "auth_token_secret_recovery_window_in_days must be 0 or between 7 and 30."
  }
}

# Raw Statement entries from another component's own ready-made IAM policy
# document (JSON, {Version, Statement}) folded into rotation_policy --
# typically the secretsmanager component's secret_access_policy output for
# the secret holding this cache's auth_token, wired in via !terraform.state.
# Lets a single Secrets Manager rotation Lambda (whose custom_policy input
# accepts only one document) get both this cache's ModifyReplicationGroup
# grant and the secret's own read/write grant in one shot, without Atmos ever
# having to read two components' live state into one YAML value (which
# !terraform.state alone cannot do, and an Atmos Go template can, but only by
# requiring live state at describe/validate time too, breaking `atmos
# describe stacks`/`atmos validate stacks` for the whole stack before first
# apply) -- mirrors the kinesis component's additional_policy_json/
# combined_policy pattern. Each folded-in Statement's Sid is rewritten
# (prefixed "Additional") so it can never collide with rotation_policy's own
# Sid. Null (the default) adds nothing.
variable "additional_policy_json" {
  type        = string
  description = "An additional IAM policy document (JSON, {Version, Statement}) whose Statement entries are folded into rotation_policy -- see the comment above this variable for the full rationale"
  default     = null

  validation {
    condition     = var.additional_policy_json == null || can(jsondecode(var.additional_policy_json).Statement)
    error_message = "additional_policy_json must be null or a JSON policy document with a Statement key."
  }
}
