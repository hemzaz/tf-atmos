################################################################################
# General Configuration
################################################################################

variable "name" {
  description = "Name of the CodeDeploy application and deployment group"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.name))
    error_message = "Application name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

################################################################################
# Application Configuration
################################################################################

variable "compute_platform" {
  description = "Compute platform type (Server, Lambda, ECS)"
  type        = string

  validation {
    condition     = contains(["Server", "Lambda", "ECS"], var.compute_platform)
    error_message = "Compute platform must be Server, Lambda, or ECS."
  }
}

################################################################################
# Deployment Group - IAM Configuration
################################################################################

variable "create_service_role" {
  description = "Whether to create a new IAM service role for CodeDeploy"
  type        = bool
  default     = true
}

variable "service_role_arn" {
  description = "ARN of existing IAM role for CodeDeploy (if create_service_role is false)"
  type        = string
  default     = null
}

variable "role_permissions_boundary" {
  description = "ARN of permissions boundary to attach to IAM role"
  type        = string
  default     = null
}

################################################################################
# Deployment Group - EC2/On-Premises Configuration
################################################################################

variable "ec2_tag_filters" {
  description = "EC2 tag filters for identifying instances to deploy to"
  type = list(object({
    key   = optional(string)
    type  = optional(string) # KEY_ONLY, VALUE_ONLY, KEY_AND_VALUE
    value = optional(string)
  }))
  default = []
}

variable "ec2_tag_set" {
  description = "EC2 tag sets for more complex filtering (AND/OR logic)"
  type = list(object({
    ec2_tag_filter = list(object({
      key   = optional(string)
      type  = optional(string)
      value = optional(string)
    }))
  }))
  default = []
}

variable "on_premises_tag_filters" {
  description = "On-premises instance tag filters"
  type = list(object({
    key   = optional(string)
    type  = optional(string)
    value = optional(string)
  }))
  default = []
}

variable "autoscaling_groups" {
  description = "List of Auto Scaling Group names to deploy to"
  type        = list(string)
  default     = []
}

################################################################################
# Deployment Group - ECS Configuration
################################################################################

variable "ecs_cluster_name" {
  description = "Name of ECS cluster for ECS deployments"
  type        = string
  default     = null
}

variable "ecs_service_name" {
  description = "Name of ECS service for ECS deployments"
  type        = string
  default     = null
}

################################################################################
# Deployment Group - Lambda Configuration
################################################################################

variable "lambda_function_name" {
  description = "Name of Lambda function for Lambda deployments"
  type        = string
  default     = null
}

variable "lambda_function_alias" {
  description = "Alias of Lambda function for Lambda deployments"
  type        = string
  default     = null
}

################################################################################
# Deployment Configuration
################################################################################

variable "deployment_config_name" {
  description = "Deployment configuration name (predefined or custom)"
  type        = string
  default     = null
}

variable "create_deployment_config" {
  description = "Whether to create a custom deployment configuration"
  type        = bool
  default     = false
}

variable "deployment_config_type" {
  description = "Type of traffic routing for custom config (TimeBasedCanary, TimeBasedLinear, AllAtOnce)"
  type        = string
  default     = "TimeBasedCanary"

  validation {
    condition     = contains(["TimeBasedCanary", "TimeBasedLinear", "AllAtOnce"], var.deployment_config_type)
    error_message = "Deployment config type must be TimeBasedCanary, TimeBasedLinear, or AllAtOnce."
  }
}

variable "canary_percentage" {
  description = "Percentage of traffic to shift in first increment (for TimeBasedCanary)"
  type        = number
  default     = 10

  validation {
    condition     = var.canary_percentage >= 0 && var.canary_percentage <= 100
    error_message = "Canary percentage must be between 0 and 100."
  }
}

variable "canary_interval" {
  description = "Number of minutes between first and second traffic shifts (for TimeBasedCanary)"
  type        = number
  default     = 5

  validation {
    condition     = var.canary_interval >= 0
    error_message = "Canary interval must be non-negative."
  }
}

variable "linear_percentage" {
  description = "Percentage of traffic to shift per interval (for TimeBasedLinear)"
  type        = number
  default     = 10

  validation {
    condition     = var.linear_percentage >= 0 && var.linear_percentage <= 100
    error_message = "Linear percentage must be between 0 and 100."
  }
}

variable "linear_interval" {
  description = "Number of minutes between traffic shifts (for TimeBasedLinear)"
  type        = number
  default     = 5

  validation {
    condition     = var.linear_interval >= 0
    error_message = "Linear interval must be non-negative."
  }
}

################################################################################
# Deployment Style
################################################################################

variable "deployment_option" {
  description = "Deployment option (WITH_TRAFFIC_CONTROL, WITHOUT_TRAFFIC_CONTROL)"
  type        = string
  default     = "WITH_TRAFFIC_CONTROL"

  validation {
    condition     = contains(["WITH_TRAFFIC_CONTROL", "WITHOUT_TRAFFIC_CONTROL"], var.deployment_option)
    error_message = "Deployment option must be WITH_TRAFFIC_CONTROL or WITHOUT_TRAFFIC_CONTROL."
  }
}

variable "deployment_type" {
  description = "Deployment type (IN_PLACE, BLUE_GREEN)"
  type        = string
  default     = "IN_PLACE"

  validation {
    condition     = contains(["IN_PLACE", "BLUE_GREEN"], var.deployment_type)
    error_message = "Deployment type must be IN_PLACE or BLUE_GREEN."
  }
}

################################################################################
# Blue/Green Deployment Configuration
################################################################################

variable "blue_green_deployment_config" {
  description = "Blue/green deployment configuration"
  type = object({
    terminate_blue_instances_on_deployment_success = optional(object({
      action                           = string # TERMINATE or KEEP_ALIVE
      termination_wait_time_in_minutes = optional(number)
    }))
    deployment_ready_option = optional(object({
      action_on_timeout    = optional(string) # CONTINUE_DEPLOYMENT or STOP_DEPLOYMENT
      wait_time_in_minutes = optional(number)
    }))
    green_fleet_provisioning_option = optional(object({
      action = string # DISCOVER_EXISTING or COPY_AUTO_SCALING_GROUP
    }))
  })
  default = null
}

################################################################################
# Load Balancer Configuration
################################################################################

variable "load_balancer_info" {
  description = "Load balancer configuration for blue/green deployments"
  type = object({
    target_group_arns        = optional(list(string))
    target_group_pair = optional(object({
      prod_traffic_route_listener_arns = list(string)
      test_traffic_route_listener_arns = optional(list(string))
      target_group_name_blue           = string
      target_group_name_green          = string
    }))
    elb_info = optional(list(object({
      name = string
    })))
  })
  default = null
}

################################################################################
# Auto Rollback Configuration
################################################################################

variable "enable_auto_rollback" {
  description = "Enable automatic rollback on deployment failure or alarm"
  type        = bool
  default     = true
}

variable "auto_rollback_events" {
  description = "Events that trigger automatic rollback"
  type        = list(string)
  default     = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM"]

  validation {
    condition = alltrue([
      for event in var.auto_rollback_events : contains(["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM", "DEPLOYMENT_STOP_ON_REQUEST"], event)
    ])
    error_message = "Invalid rollback event specified."
  }
}

################################################################################
# Alarm Configuration
################################################################################

variable "alarm_configuration" {
  description = "CloudWatch alarm configuration for deployment monitoring"
  type = object({
    enabled                   = bool
    alarm_names               = optional(list(string))
    ignore_poll_alarm_failure = optional(bool)
  })
  default = null
}

################################################################################
# Trigger Configuration
################################################################################

variable "trigger_configurations" {
  description = "SNS trigger configurations for deployment events"
  type = list(object({
    trigger_name       = string
    trigger_events     = list(string)
    trigger_target_arn = string
  }))
  default = []
}

variable "trigger_events" {
  description = "Default trigger events if not specified in trigger_configurations"
  type        = list(string)
  default = [
    "DeploymentStart",
    "DeploymentSuccess",
    "DeploymentFailure",
    "DeploymentStop"
  ]
}

################################################################################
# Outdated Instances Strategy
################################################################################

variable "outdated_instances_strategy" {
  description = "Strategy for handling outdated instances (UPDATE, IGNORE)"
  type        = string
  default     = "UPDATE"

  validation {
    condition     = contains(["UPDATE", "IGNORE"], var.outdated_instances_strategy)
    error_message = "Outdated instances strategy must be UPDATE or IGNORE."
  }
}

################################################################################
# Termination Configuration
################################################################################

variable "termination_hook_enabled" {
  description = "Enable lifecycle hook for instances before termination"
  type        = bool
  default     = false
}
