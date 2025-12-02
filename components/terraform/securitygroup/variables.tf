variable "region" {
  type        = string
  description = "AWS region"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID where security groups will be created"
}

variable "security_groups" {
  type        = map(any)
  description = "Map of security groups to create"
  default     = {}
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to resources"
  default     = {}
}

# Security Group Validation and Logging
variable "enable_security_group_logging" {
  type        = bool
  description = "Enable CloudWatch logging for security group changes"
  default     = true
}

variable "enable_security_group_alarms" {
  type        = bool
  description = "Enable CloudWatch alarms for security group violations"
  default     = true
}

variable "enforce_no_public_ingress" {
  type        = bool
  description = "Enforce that no security groups allow ingress from 0.0.0.0/0 (blocks creation)"
  default     = false
}

variable "log_retention_days" {
  type        = number
  description = "Retention period for security group change logs"
  default     = 90

  validation {
    condition     = contains([0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period."
  }
}

variable "security_alarm_actions" {
  type        = list(string)
  description = "List of SNS topic ARNs for security group alarm notifications"
  default     = []
}