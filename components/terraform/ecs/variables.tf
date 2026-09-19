variable "region" {
  type        = string
  description = "AWS region"
}

variable "fargate_only" {
  type        = bool
  description = "Whether to use only Fargate for the ECS cluster"
  default     = true
}

variable "autoscaling_group_arn" {
  type        = string
  description = "ARN of the Auto Scaling Group to use with the cluster (required when fargate_only is false)"
  default     = ""

  validation {
    condition     = var.fargate_only || can(regex("^arn:aws[a-z-]*:autoscaling:", var.autoscaling_group_arn))
    error_message = "autoscaling_group_arn must be a valid Auto Scaling Group ARN when fargate_only is false."
  }
}

variable "max_scaling_step_size" {
  type        = number
  description = "Maximum step size for ECS managed scaling"
  default     = 10

  validation {
    condition     = var.max_scaling_step_size >= 1 && var.max_scaling_step_size <= 10000
    error_message = "max_scaling_step_size must be between 1 and 10000."
  }
}

variable "min_scaling_step_size" {
  type        = number
  description = "Minimum step size for ECS managed scaling"
  default     = 1

  validation {
    condition     = var.min_scaling_step_size >= 1 && var.min_scaling_step_size <= 10000
    error_message = "min_scaling_step_size must be between 1 and 10000."
  }
}

variable "target_capacity" {
  type        = number
  description = "Target capacity for ECS managed scaling (percentage)"
  default     = 100

  validation {
    condition     = var.target_capacity >= 1 && var.target_capacity <= 100
    error_message = "target_capacity must be between 1 and 100."
  }
}

variable "enable_container_insights" {
  type        = bool
  description = "Enable Container Insights for the ECS cluster"
  default     = true
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to resources"
  default     = {}
}