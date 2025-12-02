# ASG Launch Template Module - Variables
# Version: 1.0.0

variable "name_prefix" {
  description = "Name prefix for all resources"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "production", "test", "qa"], var.environment)
    error_message = "Environment must be one of: dev, staging, production, test, qa."
  }
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for Auto Scaling Group"
  type        = list(string)
}

variable "ami_id" {
  description = "AMI ID for instances (leave empty for latest Amazon Linux 2)"
  type        = string
  default     = null
}

variable "instance_type" {
  description = "Default instance type"
  type        = string
  default     = "t3.medium"
}

variable "enable_mixed_instances" {
  description = "Enable mixed instances policy for cost optimization"
  type        = bool
  default     = true
}

variable "instance_types" {
  description = "List of instance types for mixed instances policy"
  type        = list(string)
  default     = ["t3.medium", "t3a.medium", "t2.medium"]
}

variable "on_demand_base_capacity" {
  description = "Minimum on-demand instances"
  type        = number
  default     = 0
}

variable "on_demand_percentage_above_base" {
  description = "Percentage of on-demand instances above base"
  type        = number
  default     = 20
}

variable "spot_allocation_strategy" {
  description = "How to allocate Spot capacity (lowest-price, capacity-optimized, capacity-optimized-prioritized)"
  type        = string
  default     = "capacity-optimized"
}

variable "spot_max_price" {
  description = "Maximum price for Spot instances (empty for on-demand price)"
  type        = string
  default     = ""
}

variable "min_size" {
  description = "Minimum number of instances"
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Maximum number of instances"
  type        = number
  default     = 10
}

variable "desired_capacity" {
  description = "Desired number of instances"
  type        = number
  default     = 2
}

variable "enable_target_tracking_cpu" {
  description = "Enable CPU target tracking scaling"
  type        = bool
  default     = true
}

variable "cpu_target_value" {
  description = "Target CPU utilization percentage"
  type        = number
  default     = 70
}

variable "enable_target_tracking_memory" {
  description = "Enable memory target tracking (requires CloudWatch agent)"
  type        = bool
  default     = false
}

variable "memory_target_value" {
  description = "Target memory utilization percentage"
  type        = number
  default     = 80
}

variable "enable_alb_target_tracking" {
  description = "Enable ALB request count target tracking"
  type        = bool
  default     = false
}

variable "alb_target_group_arn" {
  description = "ARN of ALB target group"
  type        = string
  default     = null
}

variable "alb_target_value" {
  description = "Target requests per instance per minute"
  type        = number
  default     = 1000
}

variable "enable_scheduled_scaling" {
  description = "Enable scheduled scaling actions"
  type        = bool
  default     = false
}

variable "scheduled_actions" {
  description = "List of scheduled scaling actions"
  type = list(object({
    name               = string
    min_size           = number
    max_size           = number
    desired_capacity   = number
    recurrence         = string
  }))
  default = []
}

variable "enable_instance_refresh" {
  description = "Enable automatic instance refresh on configuration changes"
  type        = bool
  default     = true
}

variable "instance_refresh_min_healthy_percentage" {
  description = "Minimum healthy percentage during instance refresh"
  type        = number
  default     = 90
}

variable "enable_warm_pool" {
  description = "Enable warm pool for faster scaling"
  type        = bool
  default     = false
}

variable "warm_pool_min_size" {
  description = "Minimum warm pool size"
  type        = number
  default     = 0
}

variable "warm_pool_max_group_prepared_capacity" {
  description = "Maximum prepared capacity"
  type        = number
  default     = null
}

variable "user_data" {
  description = "User data script (base64 encoded)"
  type        = string
  default     = ""
}

variable "enable_imdsv2" {
  description = "Require IMDSv2 (recommended for security)"
  type        = bool
  default     = true
}

variable "enable_monitoring" {
  description = "Enable detailed monitoring"
  type        = bool
  default     = true
}

variable "enable_cloudwatch_agent" {
  description = "Install and configure CloudWatch agent"
  type        = bool
  default     = true
}

variable "health_check_type" {
  description = "Health check type (EC2 or ELB)"
  type        = string
  default     = "EC2"
}

variable "health_check_grace_period" {
  description = "Health check grace period in seconds"
  type        = number
  default     = 300
}

variable "default_cooldown" {
  description = "Default cooldown period in seconds"
  type        = number
  default     = 300
}

variable "termination_policies" {
  description = "List of termination policies"
  type        = list(string)
  default     = ["OldestLaunchTemplate", "OldestInstance"]
}

variable "enabled_metrics" {
  description = "List of CloudWatch metrics to enable"
  type        = list(string)
  default = [
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupMaxSize",
    "GroupMinSize",
    "GroupPendingInstances",
    "GroupStandbyInstances",
    "GroupTerminatingInstances",
    "GroupTotalInstances"
  ]
}

variable "protect_from_scale_in" {
  description = "Protect instances from scale-in"
  type        = bool
  default     = false
}

variable "key_name" {
  description = "SSH key pair name"
  type        = string
  default     = null
}

variable "iam_instance_profile" {
  description = "IAM instance profile name"
  type        = string
  default     = null
}

variable "security_group_ids" {
  description = "List of security group IDs"
  type        = list(string)
  default     = []
}

variable "block_device_mappings" {
  description = "Block device mappings"
  type = list(object({
    device_name = string
    ebs = object({
      volume_size           = number
      volume_type           = string
      iops                  = optional(number)
      throughput            = optional(number)
      encrypted             = optional(bool, true)
      delete_on_termination = optional(bool, true)
    })
  }))
  default = [{
    device_name = "/dev/xvda"
    ebs = {
      volume_size = 20
      volume_type = "gp3"
      encrypted   = true
    }
  }]
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
