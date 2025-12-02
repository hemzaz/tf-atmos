# ECS Fargate Service Module - Variables
# Version: 1.0.0

# ==============================================================================
# NAMING AND TAGGING
# ==============================================================================

variable "name_prefix" {
  description = "Name prefix for all resources"
  type        = string

  validation {
    condition     = length(var.name_prefix) > 0 && length(var.name_prefix) <= 32
    error_message = "Name prefix must be between 1 and 32 characters."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, production)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "production", "test", "qa"], var.environment)
    error_message = "Environment must be one of: dev, staging, production, test, qa."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# ==============================================================================
# CLUSTER CONFIGURATION
# ==============================================================================

variable "create_cluster" {
  description = "Whether to create a new ECS cluster or use an existing one"
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "Name of the ECS cluster (required if create_cluster is false)"
  type        = string
  default     = null
}

variable "enable_container_insights" {
  description = "Enable CloudWatch Container Insights for the cluster"
  type        = bool
  default     = true
}

variable "enable_execute_command" {
  description = "Enable ECS Exec for debugging containers"
  type        = bool
  default     = true
}

# ==============================================================================
# SERVICE CONFIGURATION
# ==============================================================================

variable "service_name" {
  description = "Name of the ECS service"
  type        = string
}

variable "desired_count" {
  description = "Desired number of tasks to run"
  type        = number
  default     = 2

  validation {
    condition     = var.desired_count >= 0 && var.desired_count <= 1000
    error_message = "Desired count must be between 0 and 1000."
  }
}

variable "enable_deployment_circuit_breaker" {
  description = "Enable deployment circuit breaker for automatic rollback"
  type        = bool
  default     = true
}

variable "deployment_maximum_percent" {
  description = "Upper limit of tasks allowed during deployment (percentage)"
  type        = number
  default     = 200

  validation {
    condition     = var.deployment_maximum_percent >= 100 && var.deployment_maximum_percent <= 200
    error_message = "Maximum percent must be between 100 and 200."
  }
}

variable "deployment_minimum_healthy_percent" {
  description = "Lower limit of healthy tasks during deployment (percentage)"
  type        = number
  default     = 100

  validation {
    condition     = var.deployment_minimum_healthy_percent >= 0 && var.deployment_minimum_healthy_percent <= 100
    error_message = "Minimum healthy percent must be between 0 and 100."
  }
}

variable "health_check_grace_period_seconds" {
  description = "Seconds to ignore failing health checks after service starts (0 to disable)"
  type        = number
  default     = 60

  validation {
    condition     = var.health_check_grace_period_seconds >= 0 && var.health_check_grace_period_seconds <= 2147483647
    error_message = "Health check grace period must be between 0 and 2147483647 seconds."
  }
}

variable "force_new_deployment" {
  description = "Force a new deployment of the service on apply"
  type        = bool
  default     = false
}

# ==============================================================================
# NETWORKING
# ==============================================================================

variable "vpc_id" {
  description = "ID of the VPC where service will be deployed"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for the service (should be private subnets)"
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "At least 2 subnet IDs are required for high availability."
  }
}

variable "assign_public_ip" {
  description = "Assign public IP addresses to tasks (only for public subnets)"
  type        = bool
  default     = false
}

variable "security_group_ids" {
  description = "List of security group IDs to attach to the service (leave empty to create default)"
  type        = list(string)
  default     = []
}

variable "allowed_cidr_blocks" {
  description = "List of CIDR blocks allowed to access the service (used if security_group_ids is empty)"
  type        = list(string)
  default     = ["10.0.0.0/8"]
}

# ==============================================================================
# TASK DEFINITION
# ==============================================================================

variable "cpu" {
  description = "CPU units for the task (256, 512, 1024, 2048, 4096, 8192, 16384)"
  type        = number
  default     = 256

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096, 8192, 16384], var.cpu)
    error_message = "CPU must be one of: 256, 512, 1024, 2048, 4096, 8192, 16384."
  }
}

variable "memory" {
  description = "Memory (MB) for the task. Must be valid for selected CPU value"
  type        = number
  default     = 512

  validation {
    condition     = var.memory >= 512 && var.memory <= 122880
    error_message = "Memory must be between 512 MB and 122880 MB (120 GB)."
  }
}

variable "container_definitions" {
  description = "Container definitions for the task (JSON string or list of container definition objects)"
  type        = any
}

variable "task_role_arn" {
  description = "ARN of IAM role for task (leave empty to create default)"
  type        = string
  default     = null
}

variable "execution_role_arn" {
  description = "ARN of IAM execution role for task (leave empty to create default)"
  type        = string
  default     = null
}

variable "task_role_policies" {
  description = "List of IAM policy ARNs to attach to the task role (if creating default)"
  type        = list(string)
  default     = []
}

variable "ephemeral_storage_size_gb" {
  description = "Size of ephemeral storage in GB (20-200 GB)"
  type        = number
  default     = 20

  validation {
    condition     = var.ephemeral_storage_size_gb >= 20 && var.ephemeral_storage_size_gb <= 200
    error_message = "Ephemeral storage must be between 20 and 200 GB."
  }
}

variable "runtime_platform" {
  description = "Runtime platform configuration"
  type = object({
    operating_system_family = optional(string, "LINUX")
    cpu_architecture        = optional(string, "X86_64")
  })
  default = {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }
}

# ==============================================================================
# LOAD BALANCER CONFIGURATION
# ==============================================================================

variable "enable_load_balancer" {
  description = "Enable Application Load Balancer integration"
  type        = bool
  default     = true
}

variable "target_group_arn" {
  description = "ARN of the target group (required if enable_load_balancer is true)"
  type        = string
  default     = null
}

variable "container_name" {
  description = "Name of the container to associate with the load balancer"
  type        = string
  default     = "app"
}

variable "container_port" {
  description = "Port on the container to associate with the load balancer"
  type        = number
  default     = 8080

  validation {
    condition     = var.container_port > 0 && var.container_port <= 65535
    error_message = "Container port must be between 1 and 65535."
  }
}

# ==============================================================================
# SERVICE DISCOVERY
# ==============================================================================

variable "enable_service_discovery" {
  description = "Enable AWS Cloud Map service discovery"
  type        = bool
  default     = false
}

variable "service_discovery_namespace_id" {
  description = "ID of the Cloud Map namespace (required if enable_service_discovery is true)"
  type        = string
  default     = null
}

variable "service_discovery_dns_ttl" {
  description = "TTL for the service discovery DNS record (seconds)"
  type        = number
  default     = 10

  validation {
    condition     = var.service_discovery_dns_ttl >= 0 && var.service_discovery_dns_ttl <= 2147483647
    error_message = "DNS TTL must be between 0 and 2147483647 seconds."
  }
}

variable "service_discovery_dns_type" {
  description = "DNS record type for service discovery (A or SRV)"
  type        = string
  default     = "A"

  validation {
    condition     = contains(["A", "SRV"], var.service_discovery_dns_type)
    error_message = "DNS type must be either A or SRV."
  }
}

variable "service_discovery_routing_policy" {
  description = "Routing policy for service discovery (MULTIVALUE or WEIGHTED)"
  type        = string
  default     = "MULTIVALUE"

  validation {
    condition     = contains(["MULTIVALUE", "WEIGHTED"], var.service_discovery_routing_policy)
    error_message = "Routing policy must be either MULTIVALUE or WEIGHTED."
  }
}

# ==============================================================================
# AUTO-SCALING CONFIGURATION
# ==============================================================================

variable "enable_autoscaling" {
  description = "Enable auto-scaling for the service"
  type        = bool
  default     = true
}

variable "autoscaling_min_capacity" {
  description = "Minimum number of tasks for auto-scaling"
  type        = number
  default     = 2

  validation {
    condition     = var.autoscaling_min_capacity >= 0 && var.autoscaling_min_capacity <= 1000
    error_message = "Minimum capacity must be between 0 and 1000."
  }
}

variable "autoscaling_max_capacity" {
  description = "Maximum number of tasks for auto-scaling"
  type        = number
  default     = 10

  validation {
    condition     = var.autoscaling_max_capacity >= 1 && var.autoscaling_max_capacity <= 1000
    error_message = "Maximum capacity must be between 1 and 1000."
  }
}

variable "cpu_target_value" {
  description = "Target CPU utilization percentage for auto-scaling"
  type        = number
  default     = 70

  validation {
    condition     = var.cpu_target_value > 0 && var.cpu_target_value <= 100
    error_message = "CPU target value must be between 1 and 100."
  }
}

variable "memory_target_value" {
  description = "Target memory utilization percentage for auto-scaling"
  type        = number
  default     = 80

  validation {
    condition     = var.memory_target_value > 0 && var.memory_target_value <= 100
    error_message = "Memory target value must be between 1 and 100."
  }
}

variable "enable_alb_target_tracking" {
  description = "Enable ALB request count target tracking"
  type        = bool
  default     = false
}

variable "alb_target_value" {
  description = "Target number of ALB requests per target per minute"
  type        = number
  default     = 1000

  validation {
    condition     = var.alb_target_value > 0
    error_message = "ALB target value must be greater than 0."
  }
}

variable "scale_in_cooldown" {
  description = "Cooldown period (seconds) after scale-in activity"
  type        = number
  default     = 300

  validation {
    condition     = var.scale_in_cooldown >= 0 && var.scale_in_cooldown <= 3600
    error_message = "Scale-in cooldown must be between 0 and 3600 seconds."
  }
}

variable "scale_out_cooldown" {
  description = "Cooldown period (seconds) after scale-out activity"
  type        = number
  default     = 60

  validation {
    condition     = var.scale_out_cooldown >= 0 && var.scale_out_cooldown <= 3600
    error_message = "Scale-out cooldown must be between 0 and 3600 seconds."
  }
}

# ==============================================================================
# LOGGING AND MONITORING
# ==============================================================================

variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch Logs for the service"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain logs in CloudWatch"
  type        = number
  default     = 7

  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180,
      365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention must be a valid CloudWatch Logs retention period."
  }
}

variable "log_group_name" {
  description = "Name of the CloudWatch Log Group (leave empty to auto-generate)"
  type        = string
  default     = null
}

variable "enable_xray_tracing" {
  description = "Enable AWS X-Ray tracing"
  type        = bool
  default     = false
}

# ==============================================================================
# SECRETS AND ENVIRONMENT VARIABLES
# ==============================================================================

variable "secrets" {
  description = "Map of secret names to ARNs for injecting into containers"
  type        = map(string)
  default     = {}
}

variable "environment_variables" {
  description = "Map of environment variable names to values"
  type        = map(string)
  default     = {}
}

# ==============================================================================
# VOLUMES (EFS)
# ==============================================================================

variable "enable_efs_volumes" {
  description = "Enable EFS volumes for persistent storage"
  type        = bool
  default     = false
}

variable "efs_volumes" {
  description = "List of EFS volume configurations"
  type = list(object({
    name            = string
    file_system_id  = string
    root_directory  = optional(string, "/")
    transit_encryption = optional(string, "ENABLED")
    access_point_id = optional(string)
  }))
  default = []
}

# ==============================================================================
# DEPLOYMENT CONFIGURATION (BLUE/GREEN)
# ==============================================================================

variable "enable_blue_green_deployment" {
  description = "Enable CodeDeploy blue/green deployments"
  type        = bool
  default     = false
}

variable "deployment_config_name" {
  description = "CodeDeploy deployment configuration name"
  type        = string
  default     = "CodeDeployDefault.ECSAllAtOnce"

  validation {
    condition = contains([
      "CodeDeployDefault.ECSLinear10PercentEvery1Minutes",
      "CodeDeployDefault.ECSLinear10PercentEvery3Minutes",
      "CodeDeployDefault.ECSCanary10Percent5Minutes",
      "CodeDeployDefault.ECSCanary10Percent15Minutes",
      "CodeDeployDefault.ECSAllAtOnce"
    ], var.deployment_config_name)
    error_message = "Deployment config must be a valid CodeDeploy ECS configuration."
  }
}

variable "termination_wait_time" {
  description = "Time (minutes) to wait before terminating original task set during blue/green"
  type        = number
  default     = 5

  validation {
    condition     = var.termination_wait_time >= 0 && var.termination_wait_time <= 2880
    error_message = "Termination wait time must be between 0 and 2880 minutes (48 hours)."
  }
}

# ==============================================================================
# COST OPTIMIZATION
# ==============================================================================

variable "enable_fargate_spot" {
  description = "Enable Fargate Spot for cost optimization (not suitable for all workloads)"
  type        = bool
  default     = false
}

variable "fargate_spot_weight" {
  description = "Weight for Fargate Spot capacity provider (0-100, 0 disables)"
  type        = number
  default     = 50

  validation {
    condition     = var.fargate_spot_weight >= 0 && var.fargate_spot_weight <= 100
    error_message = "Fargate Spot weight must be between 0 and 100."
  }
}

variable "fargate_base_weight" {
  description = "Weight for Fargate (on-demand) capacity provider (0-100)"
  type        = number
  default     = 50

  validation {
    condition     = var.fargate_base_weight >= 0 && var.fargate_base_weight <= 100
    error_message = "Fargate base weight must be between 0 and 100."
  }
}
