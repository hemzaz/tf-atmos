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
  description = "ARN of the Auto Scaling Group to use with the cluster"
  default     = ""
}

variable "max_scaling_step_size" {
  type        = number
  description = "Maximum step size for ECS managed scaling"
  default     = 10
}

variable "min_scaling_step_size" {
  type        = number
  description = "Minimum step size for ECS managed scaling"
  default     = 1
}

variable "target_capacity" {
  type        = number
  description = "Target capacity for ECS managed scaling (percentage)"
  default     = 100
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