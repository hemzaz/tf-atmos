# EKS Backend Services Variables

variable "tags" {
  type        = map(string)
  description = "Tags to apply to resources"
  default     = {}
}

variable "environment" {
  type        = string
  description = "Environment name (dev, staging, prod)"
}

# Service Images
variable "api_gateway_image" {
  type        = string
  description = "Docker image for the API Gateway service"
  default     = "nginx:1.25-alpine"
}

variable "platform_api_image" {
  type        = string
  description = "Docker image for the Platform API service"
  default     = "platform-api:latest"
}

variable "auth_service_image" {
  type        = string
  description = "Docker image for the Authentication service"
  default     = "auth-service:latest"
}

variable "job_processor_image" {
  type        = string
  description = "Docker image for the Job Processor service"
  default     = "job-processor:latest"
}

# Service Versions
variable "service_versions" {
  type        = map(string)
  description = "Version labels for each service"
  default = {
    api_gateway    = "v1.0.0"
    platform_api   = "v1.0.0"
    auth_service   = "v1.0.0"
    job_processor  = "v1.0.0"
  }
}

# Database Configuration
variable "database_url" {
  type        = string
  description = "Database connection URL"
  sensitive   = true
}

variable "database_username" {
  type        = string
  description = "Database username"
  default     = "postgres"
}

variable "database_password" {
  type        = string
  description = "Database password"
  sensitive   = true
}

# Redis Configuration
variable "redis_url" {
  type        = string
  description = "Redis connection URL"
  sensitive   = true
}

variable "redis_password" {
  type        = string
  description = "Redis password"
  sensitive   = true
}

# Service Configuration
variable "service_configs" {
  type        = map(map(string))
  description = "Configuration maps for each service"
  default = {
    api_gateway = {
      "worker_processes" = "auto"
      "worker_connections" = "1024"
      "keepalive_timeout" = "65"
    }
    platform_api = {
      "max_connections" = "100"
      "connection_timeout" = "30"
      "read_timeout" = "30"
    }
    auth_service = {
      "jwt_expiry" = "3600"
      "refresh_token_expiry" = "604800"
      "bcrypt_rounds" = "12"
    }
    job_processor = {
      "max_workers" = "4"
      "queue_size" = "1000"
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
  description = "Enable Prometheus monitoring with ServiceMonitor resources"
  default     = true
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

# Feature Flags
variable "enable_service_mesh" {
  type        = bool
  description = "Enable service mesh (Istio) integration"
  default     = true
}

variable "enable_network_policies" {
  type        = bool
  description = "Enable Kubernetes network policies"
  default     = true
}

variable "enable_pod_security_policies" {
  type        = bool
  description = "Enable pod security policies"
  default     = true
}

# Performance Tuning
variable "enable_jvm_optimizations" {
  type        = bool
  description = "Enable JVM optimizations for Java services"
  default     = false
}

variable "enable_connection_pooling" {
  type        = bool
  description = "Enable database connection pooling"
  default     = true
}

# Backup and Recovery
variable "enable_velero_backups" {
  type        = bool
  description = "Enable Velero backups for persistent data"
  default     = false
}

variable "backup_schedule" {
  type        = string
  description = "Backup schedule in cron format"
  default     = "0 2 * * *" # Daily at 2 AM
}

# Development and Testing
variable "enable_debug_mode" {
  type        = bool
  description = "Enable debug mode for development"
  default     = false
}

variable "enable_hot_reload" {
  type        = bool
  description = "Enable hot reload for development"
  default     = false
}

# Load Testing
variable "enable_load_testing" {
  type        = bool
  description = "Enable load testing resources"
  default     = false
}

variable "load_test_scenarios" {
  type        = list(string)
  description = "Load test scenarios to execute"
  default     = ["baseline", "stress", "spike"]
}

# Chaos Engineering
variable "enable_chaos_engineering" {
  type        = bool
  description = "Enable chaos engineering experiments"
  default     = false
}

variable "chaos_experiments" {
  type        = list(string)
  description = "Chaos experiments to run"
  default     = ["pod-failure", "network-delay", "cpu-stress"]
}

# Cost Optimization
variable "enable_spot_instances" {
  type        = bool
  description = "Allow scheduling on spot instances"
  default     = false
}

variable "enable_vertical_pod_autoscaling" {
  type        = bool
  description = "Enable Vertical Pod Autoscaling"
  default     = false
}

# Regional Configuration
variable "multi_region_deployment" {
  type        = bool
  description = "Enable multi-region deployment"
  default     = false
}

variable "regions" {
  type        = list(string)
  description = "Regions for multi-region deployment"
  default     = ["us-west-2", "us-east-1"]
}