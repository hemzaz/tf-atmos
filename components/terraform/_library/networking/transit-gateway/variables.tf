variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "description" {
  description = "Description of the Transit Gateway"
  type        = string
  default     = "Managed by Terraform"
}

variable "amazon_side_asn" {
  description = "Private ASN for Amazon side of BGP session (64512-65534, 4200000000-4294967294)"
  type        = number
  default     = 64512

  validation {
    condition = (
      (var.amazon_side_asn >= 64512 && var.amazon_side_asn <= 65534) ||
      (var.amazon_side_asn >= 4200000000 && var.amazon_side_asn <= 4294967294)
    )
    error_message = "Amazon side ASN must be in range 64512-65534 or 4200000000-4294967294."
  }
}

variable "auto_accept_shared_attachments" {
  description = "Automatically accept cross-account attachments"
  type        = bool
  default     = false
}

variable "default_route_table_association" {
  description = "Enable default route table association"
  type        = bool
  default     = true
}

variable "default_route_table_propagation" {
  description = "Enable default route table propagation"
  type        = bool
  default     = true
}

variable "dns_support" {
  description = "Enable DNS support"
  type        = bool
  default     = true
}

variable "vpn_ecmp_support" {
  description = "Enable VPN ECMP (Equal Cost Multi-Path) support"
  type        = bool
  default     = true
}

variable "multicast_support" {
  description = "Enable multicast support"
  type        = bool
  default     = false
}

variable "transit_gateway_cidr_blocks" {
  description = "CIDR blocks for Transit Gateway Connect and VPN attachments"
  type        = list(string)
  default     = []
}

variable "vpc_attachments" {
  description = "Map of VPC attachments to create"
  type = map(object({
    vpc_id                           = string
    subnet_ids                       = list(string)
    dns_support                      = optional(bool, true)
    ipv6_support                     = optional(bool, false)
    appliance_mode_support           = optional(bool, false)
    default_route_table_association  = optional(bool, true)
    default_route_table_propagation  = optional(bool, true)
    route_table_id                   = optional(string)
    propagate_to_route_tables        = optional(list(string), [])
    tags                             = optional(map(string), {})
  }))
  default = {}
}

variable "vpn_attachments" {
  description = "Map of VPN attachments to create"
  type = map(object({
    bgp_asn                    = number
    ip_address                 = string
    static_routes_only         = optional(bool, false)
    route_table_id             = optional(string)
    propagate_to_route_tables  = optional(list(string), [])
  }))
  default = {}
}

variable "transit_gateway_route_tables" {
  description = "Map of Transit Gateway route tables to create"
  type = map(object({
    routes = optional(list(object({
      destination_cidr_block = string
      attachment_key         = optional(string)
      blackhole              = optional(bool, false)
    })), [])
  }))
  default = {}
}

variable "enable_ram_sharing" {
  description = "Enable RAM sharing for cross-account access"
  type        = bool
  default     = false
}

variable "ram_allow_external_principals" {
  description = "Allow sharing to external AWS accounts"
  type        = bool
  default     = false
}

variable "ram_principals" {
  description = "List of AWS account IDs, OUs, or organization ARN to share with"
  type        = list(string)
  default     = []
}

variable "peering_attachments" {
  description = "Map of Transit Gateway peering attachments"
  type = map(object({
    peer_region             = string
    peer_transit_gateway_id = string
  }))
  default = {}
}

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}
