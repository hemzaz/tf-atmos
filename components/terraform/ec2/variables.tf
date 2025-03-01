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
    instance_type                = string
    ami_id                       = optional(string)
    key_name                     = optional(string)
    subnet_id                    = optional(string)
    user_data                    = optional(string)
    detailed_monitoring          = optional(bool, false)
    ebs_optimized                = optional(bool, true)
    enabled                      = optional(bool, true)
    root_volume_type             = optional(string, "gp3")
    root_volume_size             = optional(number, 20)
    root_volume_delete_on_termination = optional(bool, true)
    root_volume_encrypted        = optional(bool, true)
    root_volume_kms_key_id       = optional(string)
    ebs_block_devices            = optional(list(object({
      device_name               = string
      volume_type               = optional(string, "gp3")
      volume_size               = number
      iops                      = optional(number)
      throughput                = optional(number)
      delete_on_termination     = optional(bool, true)
      encrypted                 = optional(bool, true)
      kms_key_id                = optional(string)
    })), [])
    allowed_ingress_rules        = optional(list(object({
      from_port                 = number
      to_port                   = number
      protocol                  = string
      cidr_blocks               = optional(list(string))
      security_groups           = optional(list(string))
      description               = optional(string)
    })), []),
    allowed_egress_rules         = optional(list(object({
      from_port                 = number
      to_port                   = number
      protocol                  = string
      cidr_blocks               = optional(list(string))
      security_groups           = optional(list(string))
      description               = optional(string)
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
