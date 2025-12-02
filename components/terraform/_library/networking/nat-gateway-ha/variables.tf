variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway deployment"
  type        = bool
  default     = true
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs (one NAT Gateway per subnet/AZ)"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs to route through NAT Gateways"
  type        = list(string)
}

variable "availability_zones" {
  description = "List of availability zones matching subnet order"
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) > 0
    error_message = "At least one availability zone must be specified."
  }
}

variable "internet_gateway_id" {
  description = "Internet Gateway ID (for dependency)"
  type        = string
  default     = null
}

variable "enable_cloudwatch_alarms" {
  description = "Enable CloudWatch alarms for NAT Gateway monitoring"
  type        = bool
  default     = true
}

variable "alarm_sns_topic_arns" {
  description = "List of SNS topic ARNs for alarm notifications"
  type        = list(string)
  default     = []
}

variable "bandwidth_alarm_threshold_mbps" {
  description = "Bandwidth alarm threshold in Mbps (0 to disable)"
  type        = number
  default     = 1000

  validation {
    condition     = var.bandwidth_alarm_threshold_mbps >= 0
    error_message = "Bandwidth threshold must be non-negative."
  }
}

variable "create_cloudwatch_dashboard" {
  description = "Create CloudWatch dashboard for NAT Gateway monitoring"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}
