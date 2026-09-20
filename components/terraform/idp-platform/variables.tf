# Variables for IDP Platform Infrastructure Component

variable "region" {
  type        = string
  description = "AWS region"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-\\d+$", var.region))
    error_message = "The region must be a valid AWS region name (e.g., us-east-1, eu-west-1)."
  }
}

variable "environment" {
  type        = string
  description = "Environment name; also the name prefix, matching the <environment>-vpc VPC to deploy into"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "tags" {
  type        = map(string)
  description = "Common tags applied to all resources via the provider default_tags"
  default     = {}
}

variable "acknowledge_unsupported" {
  type        = bool
  description = "Acknowledge that idp-platform is unsupported (nests root components with provider blocks); planning fails while false"
  default     = false
}

variable "secrets_version" {
  type        = number
  description = "Version of the write-only Redis auth token and JWT secret; increment to rotate both"
  default     = 1

  validation {
    condition     = var.secrets_version >= 1 && floor(var.secrets_version) == var.secrets_version
    error_message = "secrets_version must be a positive integer."
  }
}

variable "cluster_version" {
  type        = string
  description = "EKS cluster version"
  default     = "1.28"

  validation {
    condition     = can(regex("^1\\.(2[4-9]|[3-9][0-9])$", var.cluster_version))
    error_message = "Cluster version must be 1.24 or higher."
  }
}

variable "cluster_endpoint_public_access" {
  type        = bool
  description = "Enable public API server endpoint; requires cluster_endpoint_public_access_cidrs"
  default     = false
}

variable "cluster_endpoint_public_access_cidrs" {
  type        = list(string)
  description = "CIDR blocks that can access the public API server endpoint"
  default     = [] # Require explicit CIDR configuration - no default public access

  validation {
    condition = alltrue([
      for cidr in var.cluster_endpoint_public_access_cidrs : can(cidrhost(cidr, 0))
    ])
    error_message = "All values must be valid CIDR blocks."
  }
}

variable "domain_name" {
  type        = string
  description = "Primary domain name for the IDP platform"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]\\.[a-zA-Z]{2,}$", var.domain_name))
    error_message = "Domain name must be a valid DNS domain."
  }
}

variable "database_engine_version" {
  type        = string
  description = "PostgreSQL engine version"
  default     = "15.4"

  validation {
    condition     = can(regex("^1[2-9]\\.[0-9]+$", var.database_engine_version))
    error_message = "Database engine version must be PostgreSQL 12 or higher."
  }
}

variable "database_instance_class" {
  type        = string
  description = "RDS instance class"
  default     = "db.r6g.large"

  validation {
    condition = contains([
      "db.t4g.micro", "db.t4g.small", "db.t4g.medium", "db.t4g.large",
      "db.r6g.large", "db.r6g.xlarge", "db.r6g.2xlarge", "db.r6g.4xlarge",
      "db.r6i.large", "db.r6i.xlarge", "db.r6i.2xlarge", "db.r6i.4xlarge"
    ], var.database_instance_class)
    error_message = "Database instance class must be a supported RDS instance type."
  }
}

variable "database_allocated_storage" {
  type        = number
  description = "Initial allocated storage in GB"
  default     = 100

  validation {
    condition     = var.database_allocated_storage >= 20 && var.database_allocated_storage <= 65536
    error_message = "Allocated storage must be between 20 and 65536 GB."
  }
}

variable "database_max_allocated_storage" {
  type        = number
  description = "Maximum allocated storage in GB for autoscaling"
  default     = 1000

  validation {
    condition     = var.database_max_allocated_storage >= var.database_allocated_storage
    error_message = "Maximum allocated storage must be greater than or equal to allocated storage."
  }
}

variable "redis_node_type" {
  type        = string
  description = "ElastiCache Redis node type"
  default     = "cache.r7g.large"

  validation {
    condition = contains([
      "cache.t4g.micro", "cache.t4g.small", "cache.t4g.medium",
      "cache.r7g.large", "cache.r7g.xlarge", "cache.r7g.2xlarge",
      "cache.r6g.large", "cache.r6g.xlarge", "cache.r6g.2xlarge"
    ], var.redis_node_type)
    error_message = "Redis node type must be a supported ElastiCache instance type."
  }
}

variable "redis_num_cache_clusters" {
  type        = number
  description = "Number of Redis cache clusters for high availability"
  default     = 2

  validation {
    condition     = var.redis_num_cache_clusters >= 1 && var.redis_num_cache_clusters <= 6
    error_message = "Number of cache clusters must be between 1 and 6."
  }
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  description = "CIDR blocks allowed to access the platform"
  default     = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]

  validation {
    condition = alltrue([
      for cidr in var.allowed_cidr_blocks : can(cidrhost(cidr, 0))
    ])
    error_message = "All values must be valid CIDR blocks."
  }
}

variable "resource_tags" {
  type        = map(string)
  description = "Additional resource tags"
  default     = {}

  validation {
    condition = alltrue([
      for tag_key, tag_value in var.resource_tags :
      can(regex("^[a-zA-Z0-9+\\-=._:/@]{1,128}$", tag_key)) &&
      can(regex("^[a-zA-Z0-9+\\-=._:/@\\s]{0,256}$", tag_value))
    ])
    error_message = "Tag keys and values must comply with AWS tagging requirements."
  }
}

variable "log_retention_days" {
  type        = number
  description = "CloudWatch log retention period in days"
  default     = 30

  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period."
  }
}

variable "performance_insights_retention_period" {
  type        = number
  description = "RDS Performance Insights retention period in days"
  default     = 7

  validation {
    condition     = contains([7, 731], var.performance_insights_retention_period)
    error_message = "Performance Insights retention period must be either 7 or 731 days."
  }
}

variable "enable_deletion_protection" {
  type        = bool
  description = "Enable deletion protection for critical resources"
  default     = null # Will be determined based on environment
}

variable "maintenance_window" {
  type = object({
    database = optional(string, "sun:04:00-sun:05:00")
    redis    = optional(string, "sun:05:00-sun:07:00")
    eks      = optional(string, "sun:02:00-sun:03:00")
  })
  description = "Maintenance windows for different services"
  default = {
    database = "sun:04:00-sun:05:00"
    redis    = "sun:05:00-sun:07:00"
    eks      = "sun:02:00-sun:03:00"
  }

  validation {
    condition = alltrue([
      for window in values(var.maintenance_window) :
      can(regex("^(mon|tue|wed|thu|fri|sat|sun):[0-2][0-9]:[0-5][0-9]-(mon|tue|wed|thu|fri|sat|sun):[0-2][0-9]:[0-5][0-9]$", window))
    ])
    error_message = "Maintenance windows must be in the format 'ddd:hh:mm-ddd:hh:mm'."
  }
}

variable "backup_window" {
  type        = string
  description = "Database backup window"
  default     = "03:00-04:00"

  validation {
    condition     = can(regex("^[0-2][0-9]:[0-5][0-9]-[0-2][0-9]:[0-5][0-9]$", var.backup_window))
    error_message = "Backup window must be in the format 'hh:mm-hh:mm'."
  }
}

variable "notification_endpoints" {
  type = object({
    email = optional(list(string), [])
    slack = optional(string, "")
    teams = optional(string, "")
  })
  description = "Where the platform health alarm sends notifications. `email` addresses subscribe natively (each one gets a confirmation mail). `slack` and `teams` must be HTTPS forwarder URLs that answer SNS's SubscriptionConfirmation, NOT raw incoming-webhook URLs, which never confirm"
  default = {
    email = []
    slack = ""
    teams = ""
  }

  validation {
    condition     = alltrue([for e in var.notification_endpoints.email : can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", e))])
    error_message = "notification_endpoints.email entries must be email addresses."
  }

  validation {
    condition = alltrue([
      for url in [var.notification_endpoints.slack, var.notification_endpoints.teams] :
      url == "" || startswith(url, "https://")
    ])
    error_message = "notification_endpoints.slack and .teams must be https:// URLs, because SNS refuses plaintext HTTP subscriptions."
  }

  validation {
    condition = alltrue([
      for url in [var.notification_endpoints.slack, var.notification_endpoints.teams] :
      !can(regex("^https://hooks\\.slack\\.com/", url)) && !can(regex("\\.webhook\\.office\\.com/", url))
    ])
    error_message = "Point slack/teams at a forwarder that confirms the SNS subscription, not at the incoming-webhook URL itself: a raw webhook never answers SubscriptionConfirmation, so the subscription would stay PendingConfirmation and deliver nothing."
  }
}
