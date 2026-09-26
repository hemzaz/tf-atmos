# EKS Backend Services Variables

variable "region" {
  type        = string
  description = "AWS region (only used for data.aws_eks_cluster_auth)"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-\\d+$", var.region))
    error_message = "The region must be a valid AWS region name (e.g., us-east-1, eu-west-1)."
  }
}

variable "assume_role_arn" {
  type        = string
  description = "ARN of the IAM role to assume"
  default     = null

  validation {
    condition     = var.assume_role_arn == null || can(regex("^arn:aws:iam::[0-9]{12}:role/.+$", var.assume_role_arn))
    error_message = "The assume_role_arn must be a valid IAM role ARN or null."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to resources; must include Environment (used in resource names)"
  default     = {}

  validation {
    condition     = trimspace(lookup(var.tags, "Environment", "")) != ""
    error_message = "tags must include a non-empty Environment value."
  }
}

variable "environment" {
  type        = string
  description = "Environment name (dev, staging, prod)"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*$", var.environment))
    error_message = "environment must contain only lowercase letters, numbers, and hyphens."
  }
}

# EKS cluster connection. No aws CLI exec plugin (the CI image that runs
# `terraform validate`/`terraform test` has no aws CLI; see the repo's CI
# image parity note) -- provider.tf gets the token from data
# aws_eks_cluster_auth instead, the same pattern alb-controller-ingress-group
# uses. Fed from eks/main's outputs (eks_cluster_id / eks_cluster_endpoint /
# eks_cluster_certificate_authority_data).
variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster (eks output eks_cluster_id); data.aws_eks_cluster_auth requests a token for this cluster"
}

variable "host" {
  type        = string
  description = "API endpoint of cluster_name (eks output eks_cluster_endpoint)"

  validation {
    condition     = can(regex("^https://", var.host))
    error_message = "host must be a https:// URL."
  }
}

variable "cluster_ca_certificate" {
  type        = string
  description = "Base64 CA certificate of cluster_name (eks output eks_cluster_certificate_authority_data)"
}

# ClusterSecretStore (external-secrets/main). Required, not defaulted: the
# store's name is that component's own choice (default_cluster_secret_store_name
# output), not something this component should hardcode ahead of it existing.
variable "cluster_secret_store_name" {
  type        = string
  description = "Name of the ClusterSecretStore external-secrets/main created (its default_cluster_secret_store_name output); every ExternalSecret's secretStoreRef.name"

  validation {
    condition     = trimspace(var.cluster_secret_store_name) != ""
    error_message = "cluster_secret_store_name must not be empty."
  }
}

# Database (rds/main). Credentials never flow through a Terraform variable:
# the ExternalSecret below pulls username/password straight from the
# RDS-managed Secrets Manager secret into the cluster; only the (non-secret)
# connection coordinates are Terraform inputs.
variable "database_secret_arn" {
  type        = string
  description = "ARN of the RDS-managed master user secret (rds/main output password_secret_arn); the database-credentials ExternalSecret's remoteRef.key"

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:secretsmanager:", var.database_secret_arn))
    error_message = "database_secret_arn must be a Secrets Manager secret ARN."
  }
}

variable "database_endpoint" {
  type        = string
  description = "host:port of the database (rds/main output instance_endpoint)"

  validation {
    condition     = can(regex("^[^:]+:[0-9]+$", var.database_endpoint))
    error_message = "database_endpoint must be host:port."
  }
}

variable "database_name" {
  type        = string
  description = "Name of the database (rds/main output instance_name)"

  validation {
    condition     = trimspace(var.database_name) != ""
    error_message = "database_name must not be empty."
  }
}

# Redis (elasticache/main). Off by default: dev and staging run no
# elasticache instance today (stacks/catalog/elasticache/defaults.yaml), so
# REDIS_URL and the redis ExternalSecret only exist when a stack turns this on.
variable "redis_enabled" {
  type        = bool
  description = "Enable the redis-credentials ExternalSecret and the REDIS_URL env var. Off by default because dev/staging run no elasticache instance"
  default     = false
}

variable "redis_secret_arn" {
  type        = string
  description = "ARN of the Secrets Manager secret holding the redis AUTH token (elasticache/main output auth_token_secret_arn). Required when redis_enabled is true"
  default     = null

  validation {
    condition     = !var.redis_enabled || (var.redis_secret_arn != null && can(regex("^arn:aws[a-z-]*:secretsmanager:", var.redis_secret_arn)))
    error_message = "redis_secret_arn must be a Secrets Manager secret ARN when redis_enabled is true."
  }
}

variable "redis_host" {
  type        = string
  description = "Redis endpoint host, no port (elasticache/main output primary_endpoint_address). Required when redis_enabled is true"
  default     = null

  validation {
    condition     = !var.redis_enabled || (var.redis_host != null && trimspace(var.redis_host) != "")
    error_message = "redis_host must be set when redis_enabled is true."
  }
}

variable "redis_port" {
  type        = number
  description = "Redis port (elasticache/main output port)"
  default     = 6379
}

# Service Images. Required -- no defaults, including no "<name>:latest"
# placeholders: a stack must set every image explicitly (settings.environment
# or the catalog). The templated stack values themselves use Sprig's
# `required` so a missing settings key fails at template render time with a
# clear message; the regex below is the second line of defense in Terraform
# itself, in case a value ever *is* set to something that isn't a real
# `repository:tag`/`repository@sha256:digest` reference -- Go's text/template
# renders a missing map key as the literal string "<no value>", which is
# non-empty and would otherwise sail through Terraform's own "required
# variable" check and a bare non-empty/non-":latest" test. Requiring an
# explicit tag or digest also rejects an untagged reference like "nginx",
# which would otherwise silently pull an implicit ":latest".
variable "api_gateway_image" {
  type        = string
  description = "Docker image (repository:tag or repository@sha256:digest) for the API Gateway service. Required; must not use a \":latest\" tag"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9._/-]*(:[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}|@sha256:[a-f0-9]{64})$", var.api_gateway_image)) && !can(regex(":latest$", var.api_gateway_image))
    error_message = "api_gateway_image must be a repository with an explicit, non-\"latest\" tag or a @sha256 digest."
  }
}

variable "platform_api_image" {
  type        = string
  description = "Docker image (repository:tag or repository@sha256:digest) for the Platform API service. Required; must not use a \":latest\" tag"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9._/-]*(:[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}|@sha256:[a-f0-9]{64})$", var.platform_api_image)) && !can(regex(":latest$", var.platform_api_image))
    error_message = "platform_api_image must be a repository with an explicit, non-\"latest\" tag or a @sha256 digest."
  }
}

variable "auth_service_image" {
  type        = string
  description = "Docker image (repository:tag or repository@sha256:digest) for the Authentication service. Required; must not use a \":latest\" tag"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9._/-]*(:[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}|@sha256:[a-f0-9]{64})$", var.auth_service_image)) && !can(regex(":latest$", var.auth_service_image))
    error_message = "auth_service_image must be a repository with an explicit, non-\"latest\" tag or a @sha256 digest."
  }
}

variable "job_processor_image" {
  type        = string
  description = "Docker image (repository:tag or repository@sha256:digest) for the Job Processor service. Required; must not use a \":latest\" tag"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9._/-]*(:[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}|@sha256:[a-f0-9]{64})$", var.job_processor_image)) && !can(regex(":latest$", var.job_processor_image))
    error_message = "job_processor_image must be a repository with an explicit, non-\"latest\" tag or a @sha256 digest."
  }
}

# Service Versions
variable "service_versions" {
  type        = map(string)
  description = "Version labels for each service"
  default = {
    api_gateway   = "v1.0.0"
    platform_api  = "v1.0.0"
    auth_service  = "v1.0.0"
    job_processor = "v1.0.0"
  }
}

# Service Configuration
variable "service_configs" {
  type        = map(map(string))
  description = "Configuration maps for each service"
  default = {
    api_gateway = {
      "worker_processes"   = "auto"
      "worker_connections" = "1024"
      "keepalive_timeout"  = "65"
    }
    platform_api = {
      "max_connections"    = "100"
      "connection_timeout" = "30"
      "read_timeout"       = "30"
    }
    auth_service = {
      "jwt_expiry"           = "3600"
      "refresh_token_expiry" = "604800"
      "bcrypt_rounds"        = "12"
    }
    job_processor = {
      "max_workers" = "4"
      "queue_size"  = "1000"
      "job_timeout" = "300"
    }
  }
}

# Logging and Monitoring
variable "log_level" {
  type        = string
  description = "Log level for services"
  default     = "INFO"
  validation {
    condition     = contains(["DEBUG", "INFO", "WARN", "ERROR"], var.log_level)
    error_message = "Log level must be one of: DEBUG, INFO, WARN, ERROR."
  }
}

variable "enable_tracing" {
  type        = bool
  description = "Enable distributed tracing"
  default     = true
}

variable "enable_prometheus_monitoring" {
  type        = bool
  description = "Enable Prometheus monitoring with ServiceMonitor resources. Off by default: no component in this repo installs the Prometheus Operator or its CRDs, and kubernetes_manifest resolves the ServiceMonitor CRD's schema from the live API server at plan time -- with no Operator installed, that plan fails with \"no matches for kind ServiceMonitor\". Only turn this on once a Prometheus Operator (e.g. kube-prometheus-stack) is wired into eks-addons for the target cluster."
  default     = false
}

# Autoscaling Configuration
variable "cpu_target_utilization" {
  type        = number
  description = "CPU utilization target for autoscaling"
  default     = 70
  validation {
    condition     = var.cpu_target_utilization >= 10 && var.cpu_target_utilization <= 90
    error_message = "CPU target utilization must be between 10 and 90."
  }
}

variable "memory_target_utilization" {
  type        = number
  description = "Memory utilization target for autoscaling"
  default     = 80
  validation {
    condition     = var.memory_target_utilization >= 10 && var.memory_target_utilization <= 90
    error_message = "Memory target utilization must be between 10 and 90."
  }
}

# Security Configuration
variable "service_account_annotations" {
  type        = map(string)
  description = "Annotations for service accounts (e.g., IAM role ARNs)"
  default     = {}
}

variable "image_pull_secrets" {
  type        = list(string)
  description = "Image pull secrets for private registries"
  default     = []
}

# Database Migration
variable "enable_database_migrations" {
  type        = bool
  description = "Enable database migrations on startup"
  default     = true
}
