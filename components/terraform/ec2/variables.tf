variable "region" {
  type        = string
  description = "AWS region"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID where the instances will be created"
}

variable "subnet_ids" {
  type        = list(string)
  description = "List of subnet IDs to launch the instances in"
}

variable "default_ami_id" {
  type        = string
  description = "Default AMI ID to use for instances if not specified"
  default     = ""
}

variable "default_key_name" {
  type        = string
  description = "Default key pair name to use for SSH access if not specified"
  default     = null
}

variable "global_key_name" {
  type        = string
  description = "Name for a global SSH key that will be created for all instances not specifying their own key"
  default     = null

  validation {
    condition     = var.global_key_name == null || length(var.global_key_name) > 0
    error_message = "global_key_name must be null or a non-empty string."
  }

  validation {
    condition     = var.global_key_name == null || can(regex("^[a-zA-Z0-9-_]+$", var.global_key_name))
    error_message = "global_key_name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "create_ssh_keys" {
  type        = bool
  description = "Whether to create SSH key pairs for instances that don't specify an existing key_name"
  default     = false
}

variable "store_ssh_keys_in_secrets_manager" {
  type        = bool
  description = "Whether to store created SSH private keys in AWS Secrets Manager"
  default     = true
}

variable "ssh_key_algorithm" {
  type        = string
  description = "The algorithm to use when creating SSH key pairs"
  default     = "RSA"
}

variable "ssh_key_rsa_bits" {
  type        = number
  description = "The size of the generated RSA key in bits"
  default     = 4096
}

variable "instances" {
  type = map(object({
    instance_type                     = string
    ami_id                            = optional(string)
    key_name                          = optional(string)
    subnet_id                         = optional(string)
    user_data                         = optional(string)
    detailed_monitoring               = optional(bool, false)
    ebs_optimized                     = optional(bool, true)
    enabled                           = optional(bool, true)
    root_volume_type                  = optional(string, "gp3")
    root_volume_size                  = optional(number, 20)
    root_volume_delete_on_termination = optional(bool, true)
    root_volume_encrypted             = optional(bool, true)
    root_volume_kms_key_id            = optional(string)
    ebs_block_devices = optional(list(object({
      device_name           = string
      volume_type           = optional(string, "gp3")
      volume_size           = number
      iops                  = optional(number)
      throughput            = optional(number)
      delete_on_termination = optional(bool, true)
      encrypted             = optional(bool, true)
      kms_key_id            = optional(string)
    })), [])
    allowed_ingress_rules = optional(list(object({
      from_port       = number
      to_port         = number
      protocol        = string
      cidr_blocks     = optional(list(string))
      security_groups = optional(list(string))
      description     = optional(string)
    })), []),
    allowed_egress_rules = optional(list(object({
      from_port       = number
      to_port         = number
      protocol        = string
      cidr_blocks     = optional(list(string))
      security_groups = optional(list(string))
      description     = optional(string)
    })))
    additional_security_group_ids = optional(list(string), [])
    tags                          = optional(map(string), {})
    enable_ssm                    = optional(bool, true)
    custom_iam_policy             = optional(string, "")
  }))
  description = "Map of instance configurations"
  default     = {}

  validation {
    condition = alltrue([
      for k, v in var.instances : contains(keys(v), "instance_type")
    ])
    error_message = "Each instance configuration must specify an instance_type."
  }
}

variable "tags" {
  type        = map(string)
  description = "Common tags to apply to all resources"
  default     = {}

  validation {
    condition     = contains(keys(var.tags), "Environment")
    error_message = "The tags map must contain an 'Environment' key for resource naming."
  }

  validation {
    condition     = length(lookup(var.tags, "Environment", "")) > 0
    error_message = "The Environment tag must not be an empty string."
  }
}

# Network Security Variables
variable "vpc_endpoint_prefix_list_ids" {
  type        = list(string)
  description = "List of VPC endpoint prefix list IDs for AWS services (replaces 0.0.0.0/0 in default egress)"
  default     = []

  validation {
    condition     = length(var.vpc_endpoint_prefix_list_ids) > 0
    error_message = "VPC endpoint prefix list IDs are required for secure egress. Use data source: data.aws_prefix_list.s3 or create VPC endpoints."
  }
}

# Launch Template Variables
variable "enable_launch_templates" {
  type        = bool
  description = "Enable creation of EC2 launch templates for advanced configuration"
  default     = true
}

variable "create_instances_from_templates" {
  type        = bool
  description = "Create EC2 instances from launch templates (vs standalone instances)"
  default     = false
}

variable "enforce_imdsv2" {
  type        = bool
  description = "Enforce IMDSv2 (Instance Metadata Service v2) for security"
  default     = true
}

variable "imds_hop_limit" {
  type        = number
  description = "The desired HTTP PUT response hop limit for instance metadata requests"
  default     = 1

  validation {
    condition     = var.imds_hop_limit >= 1 && var.imds_hop_limit <= 64
    error_message = "IMDS hop limit must be between 1 and 64."
  }
}

variable "enable_instance_metadata_tags" {
  type        = bool
  description = "Enable access to instance tags via instance metadata"
  default     = false
}

variable "enable_network_interface_config" {
  type        = bool
  description = "Configure network interfaces in launch template (vs instance level)"
  default     = true
}

variable "default_ebs_optimized" {
  type        = bool
  description = "Default EBS optimization setting for instances"
  default     = true
}

variable "default_block_devices" {
  type = list(object({
    device_name           = string
    volume_size           = optional(number, 20)
    volume_type           = optional(string, "gp3")
    iops                  = optional(number)
    throughput            = optional(number)
    encrypted             = optional(bool, true)
    kms_key_id            = optional(string)
    delete_on_termination = optional(bool, true)
    snapshot_id           = optional(string)
  }))
  description = "Default block device mappings for launch templates"
  default     = []
}

variable "default_iam_instance_profile" {
  type        = string
  description = "Default IAM instance profile for instances"
  default     = null
}

variable "default_kms_key_id" {
  type        = string
  description = "Default KMS key ID for EBS volume encryption"
  default     = null
}

variable "enable_detailed_monitoring" {
  type        = bool
  description = "Enable detailed CloudWatch monitoring by default"
  default     = true
}

variable "default_disable_api_termination" {
  type        = bool
  description = "Default setting to prevent accidental instance termination"
  default     = false

  validation {
    condition     = var.environment != "prod" || var.default_disable_api_termination == true
    error_message = "API termination protection should be enabled for production environments."
  }
}

variable "enable_resource_name_dns" {
  type        = bool
  description = "Enable resource-based DNS naming"
  default     = true
}

variable "create_launch_template_dashboard" {
  type        = bool
  description = "Create CloudWatch dashboard for launch template metrics"
  default     = false
}

variable "environment" {
  type        = string
  description = "Environment name (dev, staging, prod) for validation rules"
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}
