# Web Service Component Variables

# Required variables
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

variable "vpc_id" {
  type        = string
  description = "VPC ID where the service will be deployed"
}

variable "public_subnet_ids" {
  type        = list(string)
  description = "List of public subnet IDs for the load balancer"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "List of private subnet IDs for the ECS service"
}

variable "container_image" {
  type        = string
  description = "Container image URI"
}

# Service configuration
variable "container_port" {
  type        = number
  description = "Port on which the container is listening"
  default     = 8080
}

variable "desired_count" {
  type        = number
  description = "Desired number of tasks"
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
    condition = contains([
      256, 512, 1024, 2048, 4096
    ], var.task_cpu)
    error_message = "CPU must be one of: 256, 512, 1024, 2048, 4096."
  }
}

variable "task_memory" {
  type        = number
  description = "Memory (MB) for the task"
  default     = 1024
  
  validation {
    condition = var.task_memory >= 512 && var.task_memory <= 30720
    error_message = "Memory must be between 512 MB and 30720 MB."
  }
}

variable "platform_version" {
  type        = string
  description = "Fargate platform version"
  default     = "LATEST"
}

# Load balancer configuration
variable "load_balancer_enabled" {
  type        = bool
  description = "Enable Application Load Balancer"
  default     = true
}

variable "internal_load_balancer" {
  type        = bool
  description = "Create internal load balancer"
  default     = false
}

variable "certificate_arn" {
  type        = string
  description = "ACM certificate ARN for HTTPS (optional)"
  default     = ""
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  description = "CIDR blocks allowed to access the service"
  default     = ["0.0.0.0/0"]
}

variable "deletion_protection" {
  type        = bool
  description = "Enable deletion protection for the load balancer"
  default     = false
}

# Health check configuration
variable "health_check_enabled" {
  type        = bool
  description = "Enable health checks"
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

# Auto scaling configuration
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
  default     = 70.0
  
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
  default     = 80.0
  
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

# Environment variables
variable "environment_variables" {
  type        = map(string)
  description = "Environment variables for the container"
  default     = {}
}

variable "secret_environment_variables" {
  type        = map(string)
  description = "Secret environment variables (SSM Parameter Store or Secrets Manager ARNs)"
  default     = {}
}

# ECS configuration
variable "capacity_providers" {
  type        = list(string)
  description = "ECS capacity providers"
  default     = ["FARGATE", "FARGATE_SPOT"]
}

variable "default_capacity_provider" {
  type        = string
  description = "Default capacity provider"
  default     = "FARGATE"
}

variable "enable_execute_command" {
  type        = bool
  description = "Enable ECS Exec for debugging"
  default     = false
}

variable "container_insights_enabled" {
  type        = bool
  description = "Enable Container Insights"
  default     = true
}

# Deployment configuration
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
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention must be a valid CloudWatch retention period."
  }
}

variable "access_logs_enabled" {
  type        = bool
  description = "Enable ALB access logs"
  default     = false
}

variable "access_logs_bucket" {
  type        = string
  description = "S3 bucket for ALB access logs"
  default     = ""
}

# IAM Configuration
variable "task_role_policy_document" {
  type        = string
  description = "Custom IAM policy document for the task role"
  default     = ""
}

variable "task_role_managed_policy_arns" {
  type        = list(string)
  description = "List of managed policy ARNs to attach to the task role"
  default     = []
}

# Tagging
variable "tags" {
  type        = map(string)
  description = "Additional tags to apply to resources"
  default     = {}
}