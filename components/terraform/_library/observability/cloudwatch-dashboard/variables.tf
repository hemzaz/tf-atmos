variable "name_prefix" {
  type        = string
  description = "Prefix for resource names"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.name_prefix))
    error_message = "Name prefix must contain only alphanumeric characters and hyphens."
  }
}

variable "region" {
  type        = string
  description = "AWS region for dashboard metrics"
  default     = null
}

variable "create_infrastructure_widgets" {
  type        = bool
  description = "Create infrastructure monitoring widgets (EC2, RDS, ELB)"
  default     = true
}

variable "create_application_widgets" {
  type        = bool
  description = "Create application monitoring widgets (Lambda, API Gateway)"
  default     = true
}

variable "create_cost_widgets" {
  type        = bool
  description = "Create cost monitoring widgets"
  default     = false
}

variable "create_security_widgets" {
  type        = bool
  description = "Create security monitoring widgets (WAF, CloudTrail)"
  default     = false
}

variable "custom_widgets" {
  type = list(object({
    type = string
    properties = object({
      metrics = optional(list(list(any)))
      query   = optional(string)
      region  = optional(string)
      title   = optional(string)
      period  = optional(number)
      stacked = optional(bool)
      yAxis   = optional(map(any))
    })
  }))
  description = "Custom dashboard widgets"
  default     = []
}

variable "enable_auto_discovery" {
  type        = bool
  description = "Enable automatic resource discovery for monitoring"
  default     = false
}

variable "discovery_tags" {
  type        = map(string)
  description = "Tags for auto-discovery of EC2 instances"
  default     = {}
}

variable "discovery_alb_names" {
  type        = list(string)
  description = "ALB names for auto-discovery"
  default     = []
}

variable "discovery_rds_clusters" {
  type        = list(string)
  description = "RDS cluster identifiers for auto-discovery"
  default     = []
}

variable "enable_cost_tracking" {
  type        = bool
  description = "Enable cost estimation tracking via metric filters"
  default     = false
}

variable "cost_tracking_log_group" {
  type        = string
  description = "CloudWatch log group for cost tracking"
  default     = "/aws/cost-tracking"
}

variable "custom_namespace" {
  type        = string
  description = "Custom CloudWatch namespace for metrics"
  default     = "Custom/Application"

  validation {
    condition     = can(regex("^[a-zA-Z0-9/_-]+$", var.custom_namespace))
    error_message = "Namespace must contain only alphanumeric characters, forward slashes, underscores, and hyphens."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to resources"
  default     = {}
}
