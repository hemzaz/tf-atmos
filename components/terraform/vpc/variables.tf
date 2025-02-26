variable "region" {
  type        = string
  description = "AWS region"
  default     = "eu-west-2"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC"
  
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "Must be a valid IPv4 CIDR block address."
  }
}

variable "azs" {
  type        = list(string)
  description = "Availability Zones"
}

variable "private_subnets" {
  type        = list(string)
  description = "CIDR blocks for private subnets"
  
  validation {
    condition     = length(var.private_subnets) > 0
    error_message = "At least one private subnet CIDR block must be provided."
  }
  
  validation {
    condition     = alltrue([for cidr in var.private_subnets : can(cidrhost(cidr, 0))])
    error_message = "All private subnet CIDR blocks must be valid IPv4 CIDR block addresses."
  }
}

variable "public_subnets" {
  type        = list(string)
  description = "CIDR blocks for public subnets"
  
  validation {
    condition     = length(var.public_subnets) > 0
    error_message = "At least one public subnet CIDR block must be provided."
  }
  
  validation {
    condition     = alltrue([for cidr in var.public_subnets : can(cidrhost(cidr, 0))])
    error_message = "All public subnet CIDR blocks must be valid IPv4 CIDR block addresses."
  }
}

variable "enable_nat_gateway" {
  type        = bool
  description = "Enable NAT Gateway"
  default     = true
}

variable "nat_gateway_strategy" {
  type        = string
  description = "Strategy for NAT gateway deployment: 'single' (one NAT gateway for all AZs), 'one_per_az' (one NAT gateway per AZ)"
  default     = "single"
  
  validation {
    condition     = contains(["single", "one_per_az"], var.nat_gateway_strategy)
    error_message = "NAT gateway strategy must be either 'single' or 'one_per_az'."
  }
}

variable "enable_vpn_gateway" {
  type        = bool
  description = "Enable VPN Gateway"
  default     = false
}

variable "enable_transit_gateway" {
  type        = bool
  description = "Enable Transit Gateway"
  default     = false
}

variable "transit_gateway_id" {
  type        = string
  description = "ID of an existing Transit Gateway to attach to"
  default     = ""
}

variable "ram_resource_share_arn" {
  type        = string
  description = "ARN of the Resource Access Manager (RAM) resource share"
  default     = ""
}

variable "create_vpc_iam_role" {
  type        = bool
  description = "Whether to create an IAM role for VPC management"
  default     = true
}

variable "vpc_iam_role_name" {
  type        = string
  description = "Name of the IAM role for VPC management"
  default     = ""
}

variable "default_sg_ingress_self_only" {
  type        = bool
  description = "Whether to allow only self ingress in the default security group"
  default     = true
}

variable "default_sg_egress_self_only" {
  type        = bool
  description = "Whether to allow only self egress in the default security group"
  default     = true
}

variable "default_sg_allow_all_outbound" {
  type        = bool
  description = "Whether to allow all outbound traffic in the default security group"
  default     = false
}

variable "default_security_group_ingress_rules" {
  type = list(object({
    from_port       = number
    to_port         = number
    protocol        = string
    cidr_blocks     = optional(list(string))
    security_groups = optional(list(string))
    self            = optional(bool)
    description     = optional(string)
  }))
  description = "List of ingress rules for the default security group"
  default     = []
}

variable "default_security_group_egress_rules" {
  type = list(object({
    from_port       = number
    to_port         = number
    protocol        = string
    cidr_blocks     = optional(list(string))
    security_groups = optional(list(string))
    self            = optional(bool)
    description     = optional(string)
  }))
  description = "List of egress rules for the default security group"
  default     = []
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to resources"
  default     = {}
}