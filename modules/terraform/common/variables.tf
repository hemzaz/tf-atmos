# Common variables module - Standardized variable definitions across all components
# This module provides consistent variable patterns and validation rules

# Core naming variables
variable "namespace" {
  type        = string
  description = "Namespace for resource naming (e.g., 'myorg', 'platform')"
  
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.namespace))
    error_message = "Namespace must contain only lowercase letters, numbers, and hyphens, and cannot start or end with a hyphen."
  }
  
  validation {
    condition     = length(var.namespace) >= 2 && length(var.namespace) <= 20
    error_message = "Namespace must be between 2 and 20 characters long."
  }
}

variable "environment" {
  type        = string
  description = "Environment name (dev, staging, prod)"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "stage" {
  type        = string
  description = "Stage/instance of the environment (e.g., '01', '02', 'blue', 'green')"
  default     = "01"
  
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.stage))
    error_message = "Stage must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "component_name" {
  type        = string
  description = "Name of the component (e.g., 'vpc', 'eks', 'rds')"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.component_name))
    error_message = "Component name must start with a letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "custom_name_prefix" {
  type        = string
  description = "Custom name prefix to override the default naming convention"
  default     = null
}

# AWS region and AZ configuration
variable "region" {
  type        = string
  description = "AWS region where resources will be created"
  
  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-\\d+$", var.region))
    error_message = "Must be a valid AWS region format (e.g., us-west-2, eu-central-1)."
  }
}

variable "availability_zones" {
  type        = list(string)
  description = "List of availability zones to use"
  default     = []
  
  validation {
    condition     = length(var.availability_zones) == 0 || length(var.availability_zones) >= 2
    error_message = "If specified, at least 2 availability zones must be provided for high availability."
  }
}

# Project and organization information
variable "project_name" {
  type        = string
  description = "Name of the project this infrastructure supports"
  default     = "infrastructure"
  
  validation {
    condition     = length(var.project_name) >= 1 && length(var.project_name) <= 64
    error_message = "Project name must be between 1 and 64 characters."
  }
}

variable "application_name" {
  type        = string
  description = "Name of the application using this infrastructure"
  default     = "platform"
}

variable "business_unit" {
  type        = string
  description = "Business unit responsible for this infrastructure"
  default     = "engineering"
}

variable "cost_center" {
  type        = string
  description = "Cost center for billing and cost allocation"
  default     = "infrastructure"
}

variable "owner" {
  type        = string
  description = "Owner/team responsible for this infrastructure"
  default     = "platform-team"
  
  validation {
    condition     = length(var.owner) >= 1 && length(var.owner) <= 64
    error_message = "Owner must be between 1 and 64 characters."
  }
}

# Security and compliance
variable "data_classification" {
  type        = string
  description = "Data classification level (public, internal, confidential, restricted)"
  default     = "internal"
  
  validation {
    condition     = contains(["public", "internal", "confidential", "restricted"], var.data_classification)
    error_message = "Data classification must be one of: public, internal, confidential, restricted."
  }
}

variable "compliance_frameworks" {
  type        = list(string)
  description = "List of compliance frameworks this infrastructure must adhere to"
  default     = []
  
  validation {
    condition = alltrue([
      for framework in var.compliance_frameworks :
      contains(["SOC2", "ISO27001", "GDPR", "HIPAA", "PCI-DSS", "NIST"], framework)
    ])
    error_message = "Compliance frameworks must be from: SOC2, ISO27001, GDPR, HIPAA, PCI-DSS, NIST."
  }
}

variable "backup_required" {
  type        = bool
  description = "Whether this infrastructure requires backup"
  default     = true
}

# Network configuration
variable "allowed_cidr_blocks" {
  type        = list(string)
  description = "CIDR blocks allowed to access resources"
  default     = []
  
  validation {
    condition = alltrue([
      for cidr in var.allowed_cidr_blocks :
      can(cidrhost(cidr, 0))
    ])
    error_message = "All entries must be valid CIDR blocks."
  }
}

variable "enable_ipv6" {
  type        = bool
  description = "Enable IPv6 support"
  default     = false
}

# Monitoring and logging
variable "enable_monitoring" {
  type        = bool
  description = "Enable monitoring for resources"
  default     = true
}

variable "enable_dev_monitoring" {
  type        = bool
  description = "Enable monitoring in development environment"
  default     = false
}

variable "enable_detailed_monitoring" {
  type        = bool
  description = "Enable detailed monitoring (may incur additional costs)"
  default     = false
}

variable "log_retention_days" {
  type        = number
  description = "Number of days to retain logs"
  default     = 30
  
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention must be one of the allowed CloudWatch log retention values."
  }
}

# Encryption settings
variable "enable_encryption_at_rest" {
  type        = bool
  description = "Enable encryption at rest"
  default     = true
}

variable "enable_encryption_in_transit" {
  type        = bool
  description = "Enable encryption in transit"
  default     = true
}

variable "kms_key_deletion_window" {
  type        = number
  description = "KMS key deletion window in days"
  default     = 30
  
  validation {
    condition     = var.kms_key_deletion_window >= 7 && var.kms_key_deletion_window <= 30
    error_message = "KMS key deletion window must be between 7 and 30 days."
  }
}

# High availability and disaster recovery
variable "enable_multi_az" {
  type        = bool
  description = "Enable multi-AZ deployment"
  default     = false
}

variable "enable_cross_region_backup" {
  type        = bool
  description = "Enable cross-region backup"
  default     = false
}

variable "backup_retention_days" {
  type        = number
  description = "Number of days to retain backups"
  default     = 7
  
  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 35
    error_message = "Backup retention must be between 1 and 35 days."
  }
}

# Performance and scaling
variable "performance_insights_enabled" {
  type        = bool
  description = "Enable performance insights where applicable"
  default     = false
}

variable "auto_minor_version_upgrade" {
  type        = bool
  description = "Enable automatic minor version upgrades"
  default     = true
}

# Tagging
variable "additional_tags" {
  type        = map(string)
  description = "Additional tags to apply to resources"
  default     = {}
  
  validation {
    condition = alltrue([
      for k, v in var.additional_tags :
      length(k) <= 128 && length(v) <= 256
    ])
    error_message = "Tag keys must be <= 128 characters and values <= 256 characters."
  }
}

# Version information
variable "terraform_version" {
  type        = string
  description = "Version of Terraform being used"
  default     = "1.11.0"
}

variable "module_version" {
  type        = string
  description = "Version of the Terraform module"
  default     = "1.0.0"
}

variable "deployment_id" {
  type        = string
  description = "Unique identifier for this deployment"
  default     = ""
}

# Resource-specific common variables
variable "instance_types" {
  type        = list(string)
  description = "List of EC2 instance types"
  default     = []
  
  validation {
    condition = alltrue([
      for type in var.instance_types :
      can(regex("^[a-z0-9]+\\.[a-z0-9]+$", type))
    ])
    error_message = "Instance types must be in the format 'family.size' (e.g., t3.micro, m5.large)."
  }
}

variable "enable_termination_protection" {
  type        = bool
  description = "Enable termination protection for resources"
  default     = false
}

variable "deletion_protection" {
  type        = bool
  description = "Enable deletion protection"
  default     = null
}

# Maintenance windows
variable "maintenance_window" {
  type        = string
  description = "Maintenance window for updates (day:hour:min-day:hour:min format)"
  default     = ""
  
  validation {
    condition = var.maintenance_window == "" || can(regex("^(sun|mon|tue|wed|thu|fri|sat):[0-2][0-9]:[0-5][0-9]-(sun|mon|tue|wed|thu|fri|sat):[0-2][0-9]:[0-5][0-9]$", var.maintenance_window))
    error_message = "Maintenance window must be in format 'day:hh:mm-day:hh:mm' (e.g., 'sun:03:00-sun:04:00')."
  }
}

variable "backup_window" {
  type        = string
  description = "Backup window (hh:mm-hh:mm format)"
  default     = ""
  
  validation {
    condition = var.backup_window == "" || can(regex("^[0-2][0-9]:[0-5][0-9]-[0-2][0-9]:[0-5][0-9]$", var.backup_window))
    error_message = "Backup window must be in format 'hh:mm-hh:mm' (e.g., '03:00-05:00')."
  }
}

# Feature flags for environment-specific behavior
variable "feature_flags" {
  type        = map(bool)
  description = "Feature flags to enable/disable functionality"
  default     = {}
}

# Resource quotas and limits
variable "resource_limits" {
  type = object({
    max_instances     = optional(number, 10)
    max_storage_gb    = optional(number, 1000)
    max_cpu_units     = optional(number, 100)
    max_memory_mb     = optional(number, 10240)
  })
  description = "Resource limits for safety and cost control"
  default     = {}
}

# Common timeouts
variable "timeouts" {
  type = object({
    create = optional(string, "30m")
    update = optional(string, "30m")
    delete = optional(string, "30m")
  })
  description = "Timeout values for resource operations"
  default     = {}
}