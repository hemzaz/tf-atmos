variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where firewall will be deployed"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for firewall endpoints (one per AZ)"
  type        = list(string)
}

variable "firewall_description" {
  description = "Description of the Network Firewall"
  type        = string
  default     = "Managed by Terraform"
}

variable "firewall_policy_description" {
  description = "Description of the firewall policy"
  type        = string
  default     = "Managed by Terraform"
}

variable "enable_delete_protection" {
  description = "Enable deletion protection"
  type        = bool
  default     = true
}

variable "enable_subnet_change_protection" {
  description = "Enable subnet change protection"
  type        = bool
  default     = true
}

variable "enable_policy_change_protection" {
  description = "Enable firewall policy change protection"
  type        = bool
  default     = false
}

variable "stateless_default_actions" {
  description = "Default actions for stateless traffic"
  type        = list(string)
  default     = ["aws:forward_to_sfe"]
}

variable "stateless_fragment_default_actions" {
  description = "Default actions for stateless fragments"
  type        = list(string)
  default     = ["aws:forward_to_sfe"]
}

variable "stateful_default_actions" {
  description = "Default actions for stateful traffic"
  type        = list(string)
  default     = ["aws:drop_established"]
}

variable "stateful_rule_order" {
  description = "Rule evaluation order (DEFAULT_ACTION_ORDER or STRICT_ORDER)"
  type        = string
  default     = "DEFAULT_ACTION_ORDER"

  validation {
    condition     = contains(["DEFAULT_ACTION_ORDER", "STRICT_ORDER"], var.stateful_rule_order)
    error_message = "Rule order must be DEFAULT_ACTION_ORDER or STRICT_ORDER."
  }
}

variable "stateless_rule_groups" {
  description = "Map of stateless rule groups"
  type = map(object({
    capacity    = number
    description = optional(string)
    rules = list(object({
      priority           = number
      actions            = list(string)
      source_cidrs       = optional(list(string), [])
      destination_cidrs  = optional(list(string), [])
      source_ports       = optional(list(object({
        from_port = number
        to_port   = number
      })), [])
      destination_ports  = optional(list(object({
        from_port = number
        to_port   = number
      })), [])
      protocols          = optional(list(number))
    }))
  }))
  default = {}
}

variable "stateful_domain_rule_groups" {
  description = "Map of stateful domain-based rule groups"
  type = map(object({
    capacity              = number
    description           = optional(string)
    generated_rules_type  = string # ALLOWLIST or DENYLIST
    target_types          = list(string) # ["TLS_SNI", "HTTP_HOST"]
    targets               = list(string)
    rule_order            = optional(string, "DEFAULT_ACTION_ORDER")
    ip_sets               = optional(map(list(string)), {})
  }))
  default = {}
}

variable "stateful_5tuple_rule_groups" {
  description = "Map of stateful 5-tuple rule groups"
  type = map(object({
    capacity    = number
    description = optional(string)
    rule_order  = optional(string, "DEFAULT_ACTION_ORDER")
    rules = list(object({
      action           = string
      destination      = string
      destination_port = string
      direction        = string
      protocol         = string
      source           = string
      source_port      = string
      sid              = string
    }))
  }))
  default = {}
}

variable "stateful_suricata_rule_groups" {
  description = "Map of stateful Suricata rule groups"
  type = map(object({
    capacity     = number
    description  = optional(string)
    rule_order   = optional(string, "DEFAULT_ACTION_ORDER")
    rules_string = string
  }))
  default = {}
}

variable "enable_flow_logs_to_s3" {
  description = "Enable flow logs to S3"
  type        = bool
  default     = true
}

variable "enable_flow_logs_to_cloudwatch" {
  description = "Enable flow logs to CloudWatch"
  type        = bool
  default     = false
}

variable "enable_alert_logs_to_cloudwatch" {
  description = "Enable alert logs to CloudWatch"
  type        = bool
  default     = true
}

variable "cloudwatch_log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}
