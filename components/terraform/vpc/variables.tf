variable "region" {
  type        = string
  description = "AWS region"
  default     = "eu-west-2"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC"
}

variable "azs" {
  type        = list(string)
  description = "Availability Zones"
}

variable "private_subnets" {
  type        = list(string)
  description = "CIDR blocks for private subnets"
}

variable "public_subnets" {
  type        = list(string)
  description = "CIDR blocks for public subnets"
}

variable "enable_nat_gateway" {
  type        = bool
  description = "Enable NAT Gateway"
  default     = true
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

variable "tags" {
  type        = map(string)
  description = "Tags to apply to resources"
  default     = {}
}