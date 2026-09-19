# Web Service Component Variables

# Provider
variable "region" {
  type        = string
  description = "AWS region"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-\\d+$", var.region))
    error_message = "The region must be a valid AWS region name (e.g., us-east-1, eu-west-2)."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to every resource through the provider default_tags (Tenant, Account, Environment, ManagedBy)"
  default     = {}
}

# Naming
variable "tenant" {
  type        = string
  description = "Tenant name"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.tenant))
    error_message = "Tenant must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  type        = string
  description = "Environment name"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "service_name" {
  type        = string
  description = "Name of the web service"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.service_name))
    error_message = "Service name must contain only lowercase letters, numbers, and hyphens."
  }
}

# Networking
variable "vpc_id" {
  type        = string
  description = "VPC ID where the service will be deployed"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "The vpc_id must be a valid VPC ID (vpc-...)."
  }
}

variable "public_subnet_ids" {
  type        = list(string)
  description = "Public subnet IDs for an internet-facing load balancer"
  default     = []
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs for the ECS tasks (and an internal load balancer)"

  validation {
    condition     = length(var.private_subnet_ids) > 0
    error_message = "At least one private subnet ID is required."
  }
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  description = "IPv4 CIDR blocks allowed to reach the load balancer (or the tasks when the load balancer is disabled)"
  default     = ["0.0.0.0/0"]

  validation {
    condition     = alltrue([for cidr in var.allowed_cidr_blocks : can(cidrnetmask(cidr))])
    error_message = "All allowed_cidr_blocks must be valid IPv4 CIDR blocks."
  }
}

variable "service_egress_cidr_blocks" {
  type        = list(string)
  description = "IPv4 CIDR blocks the tasks may reach (image pulls and AWS APIs need 0.0.0.0/0 unless VPC endpoints exist)"
  default     = ["0.0.0.0/0"]

  validation {
    condition     = alltrue([for cidr in var.service_egress_cidr_blocks : can(cidrnetmask(cidr))])
    error_message = "All service_egress_cidr_blocks must be valid IPv4 CIDR blocks."
  }
}

# Container
variable "container_image" {
  type        = string
  description = "Container image URI (pin a digest or immutable tag)"
}

variable "container_port" {
  type        = number
  description = "Port on which the container is listening"
  default     = 8080

  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535
    error_message = "Container port must be between 1 and 65535."
  }
}

variable "cpu_architecture" {
  type        = string
  description = "CPU architecture of the task (X86_64 or ARM64)"
  default     = "X86_64"

  validation {
    condition     = contains(["X86_64", "ARM64"], var.cpu_architecture)
    error_message = "CPU architecture must be X86_64 or ARM64."
  }
}

variable "readonly_root_filesystem" {
  type        = bool
  description = "Mount the container root filesystem read-only"
  default     = true
}

variable "desired_count" {
  type        = number
  description = "Initial number of tasks (auto scaling manages it afterwards)"
  default     = 2

  validation {
    condition     = var.desired_count >= 1
    error_message = "Desired count must be at least 1."
  }
}

variable "task_cpu" {
  type        = number
  description = "CPU units for the task (1024 = 1 vCPU)"
  default     = 512

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096, 8192, 16384], var.task_cpu)
    error_message = "CPU must be one of: 256, 512, 1024, 2048, 4096, 8192, 16384."
  }
}

variable "task_memory" {
  type        = number
  description = "Memory (MB) for the task"
  default     = 1024

  validation {
    condition     = var.task_memory >= 512 && var.task_memory <= 122880
    error_message = "Memory must be between 512 MB and 122880 MB."
  }
}

variable "platform_version" {
  type        = string
  description = "Fargate platform version"
  default     = "LATEST"
}

# Load balancer
variable "load_balancer_enabled" {
  type        = bool
  description = "Create an Application Load Balancer in front of the service"
  default     = true
}

variable "internal_load_balancer" {
  type        = bool
  description = "Create an internal load balancer in the private subnets"
  default     = false
}

variable "certificate_arn" {
  type        = string
  description = "ACM certificate ARN; enables the HTTPS listener and an HTTP redirect (null for HTTP only)"
  default     = null
}

variable "ssl_policy" {
  type        = string
  description = "TLS policy of the HTTPS listener"
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

variable "deletion_protection" {
  type        = bool
  description = "Enable deletion protection for the load balancer"
  default     = true
}

variable "access_logs_enabled" {
  type        = bool
  description = "Enable ALB access logs"
  default     = false
}

variable "access_logs_bucket" {
  type        = string
  description = "S3 bucket for ALB access logs (required when access_logs_enabled is true)"
  default     = null
}

# Target group health check
variable "health_check_enabled" {
  type        = bool
  description = "Enable target group health checks"
  default     = true
}

variable "health_check_path" {
  type        = string
  description = "Health check path"
  default     = "/health"
}

variable "health_check_matcher" {
  type        = string
  description = "Health check response codes"
  default     = "200"
}

variable "health_check_interval" {
  type        = number
  description = "Health check interval in seconds"
  default     = 30
}

variable "health_check_timeout" {
  type        = number
  description = "Health check timeout in seconds"
  default     = 5
}

variable "health_check_healthy_threshold" {
  type        = number
  description = "Healthy threshold count"
  default     = 2
}

variable "health_check_unhealthy_threshold" {
  type        = number
  description = "Unhealthy threshold count"
  default     = 2
}

# Container health check
variable "container_health_check_enabled" {
  type        = bool
  description = "Enable container health check"
  default     = true
}

variable "container_health_check_command" {
  type        = list(string)
  description = "Container health check command"
  default     = ["CMD-SHELL", "curl -f http://localhost:8080/health || exit 1"]
}

variable "container_health_check_interval" {
  type        = number
  description = "Container health check interval in seconds"
  default     = 30
}

variable "container_health_check_timeout" {
  type        = number
  description = "Container health check timeout in seconds"
  default     = 5
}

variable "container_health_check_retries" {
  type        = number
  description = "Container health check retries"
  default     = 3
}

variable "container_health_check_start_period" {
  type        = number
  description = "Container health check start period in seconds"
  default     = 60
}

# Auto scaling
variable "auto_scaling_enabled" {
  type        = bool
  description = "Enable auto scaling"
  default     = true
}

variable "auto_scaling_min_capacity" {
  type        = number
  description = "Minimum number of tasks"
  default     = 2
}

variable "auto_scaling_max_capacity" {
  type        = number
  description = "Maximum number of tasks"
  default     = 10
}

variable "auto_scaling_cpu_target" {
  type        = number
  description = "Target CPU utilization for auto scaling"
  default     = 70

  validation {
    condition     = var.auto_scaling_cpu_target > 0 && var.auto_scaling_cpu_target <= 100
    error_message = "CPU target must be between 0 and 100."
  }
}

variable "auto_scaling_memory_enabled" {
  type        = bool
  description = "Enable memory-based auto scaling"
  default     = false
}

variable "auto_scaling_memory_target" {
  type        = number
  description = "Target memory utilization for auto scaling"
  default     = 80

  validation {
    condition     = var.auto_scaling_memory_target > 0 && var.auto_scaling_memory_target <= 100
    error_message = "Memory target must be between 0 and 100."
  }
}

variable "auto_scaling_scale_out_cooldown" {
  type        = number
  description = "Scale out cooldown period in seconds"
  default     = 300
}

variable "auto_scaling_scale_in_cooldown" {
  type        = number
  description = "Scale in cooldown period in seconds"
  default     = 300
}

variable "auto_scaling_disable_scale_in" {
  type        = bool
  description = "Disable scale in"
  default     = false
}

# Environment and secrets
variable "environment_variables" {
  type        = map(string)
  description = "Plain-text environment variables for the container (never secrets)"
  default     = {}
}

variable "secret_environment_variables" {
  type        = map(string)
  description = "Secret environment variables: name => Secrets Manager secret ARN (optionally with a :json-key:: suffix) or SSM parameter ARN"
  default     = {}

  validation {
    condition = alltrue([
      for value in values(var.secret_environment_variables) :
      can(regex("^arn:[a-z-]+:(secretsmanager|ssm):", value))
    ])
    error_message = "Each secret_environment_variables value must be a Secrets Manager secret ARN or an SSM parameter ARN."
  }
}

variable "secrets_kms_key_arns" {
  type        = list(string)
  description = "Customer-managed KMS key ARNs that encrypt the referenced secrets (empty for AWS-managed keys)"
  default     = []
}

# ECS
variable "capacity_providers" {
  type        = list(string)
  description = "ECS capacity providers associated with the cluster"
  default     = ["FARGATE", "FARGATE_SPOT"]

  validation {
    condition     = alltrue([for cp in var.capacity_providers : contains(["FARGATE", "FARGATE_SPOT"], cp)])
    error_message = "Capacity providers must be FARGATE and/or FARGATE_SPOT."
  }
}

variable "default_capacity_provider" {
  type        = string
  description = "Capacity provider used by the service"
  default     = "FARGATE"

  validation {
    condition     = contains(["FARGATE", "FARGATE_SPOT"], var.default_capacity_provider)
    error_message = "Default capacity provider must be FARGATE or FARGATE_SPOT."
  }
}

variable "enable_execute_command" {
  type        = bool
  description = "Enable ECS Exec for debugging"
  default     = false
}

variable "container_insights_enabled" {
  type        = bool
  description = "Enable Container Insights (enhanced observability)"
  default     = true
}

# Deployment
variable "deployment_maximum_percent" {
  type        = number
  description = "Maximum percentage of tasks to run during deployment"
  default     = 200
}

variable "deployment_minimum_healthy_percent" {
  type        = number
  description = "Minimum percentage of healthy tasks during deployment"
  default     = 50
}

variable "deployment_circuit_breaker_enabled" {
  type        = bool
  description = "Enable deployment circuit breaker"
  default     = true
}

variable "deployment_circuit_breaker_rollback" {
  type        = bool
  description = "Enable automatic rollback on deployment failure"
  default     = true
}

# Logging
variable "log_retention_days" {
  type        = number
  description = "CloudWatch log retention in days"
  default     = 14

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "Log retention must be a valid CloudWatch retention period."
  }
}

variable "log_kms_key_arn" {
  type        = string
  description = "KMS key ARN used to encrypt the log group (null for AWS-managed encryption)"
  default     = null
}

# IAM
variable "task_role_policy_document" {
  type        = string
  description = "Custom IAM policy JSON for the task role (use an aws_iam_policy_document; null for none)"
  default     = null
}

variable "task_role_managed_policy_arns" {
  type        = list(string)
  description = "Managed policy ARNs to attach to the task role"
  default     = []
}
