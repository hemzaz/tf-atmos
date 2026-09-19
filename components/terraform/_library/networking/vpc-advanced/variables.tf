variable "name_prefix" {
  description = "Name prefix for all resources"
  type        = string

  validation {
    condition     = length(var.name_prefix) > 0 && length(var.name_prefix) <= 32
    error_message = "Name prefix must be between 1 and 32 characters."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, production)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "production", "test", "qa"], var.environment)
    error_message = "Environment must be one of: dev, staging, production, test, qa."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string

  validation {
    condition     = can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/[0-9]{1,2}$", var.vpc_cidr))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "availability_zones" {
  description = "List of availability zones in which to create subnets"
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) >= 2 && length(distinct(var.availability_zones)) == length(var.availability_zones)
    error_message = "At least 2 distinct availability zones are required for high availability."
  }
}

variable "public_subnets" {
  description = "List of public subnet CIDR blocks (one per availability zone)"
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for cidr in var.public_subnets :
      can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/[0-9]{1,2}$", cidr))
    ])
    error_message = "All public subnet CIDRs must be valid IPv4 CIDR blocks."
  }

  validation {
    condition     = length(var.public_subnets) <= length(var.availability_zones)
    error_message = "public_subnets must not have more entries than availability_zones (one subnet per AZ)."
  }
}

variable "private_subnets" {
  description = "List of private subnet CIDR blocks (one per availability zone)"
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for cidr in var.private_subnets :
      can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/[0-9]{1,2}$", cidr))
    ])
    error_message = "All private subnet CIDRs must be valid IPv4 CIDR blocks."
  }

  validation {
    condition     = length(var.private_subnets) <= length(var.availability_zones)
    error_message = "private_subnets must not have more entries than availability_zones (one subnet per AZ)."
  }
}

variable "database_subnets" {
  description = "List of database subnet CIDR blocks (one per availability zone)"
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for cidr in var.database_subnets :
      can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/[0-9]{1,2}$", cidr))
    ])
    error_message = "All database subnet CIDRs must be valid IPv4 CIDR blocks."
  }

  validation {
    condition     = length(var.database_subnets) <= length(var.availability_zones)
    error_message = "database_subnets must not have more entries than availability_zones (one subnet per AZ)."
  }
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for private subnets"
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Use a single NAT Gateway for all private subnets (cost optimization, but not HA)"
  type        = bool
  default     = false
}

variable "enable_dns_hostnames" {
  description = "Enable DNS hostnames in the VPC"
  type        = bool
  default     = true
}

variable "enable_dns_support" {
  description = "Enable DNS support in the VPC"
  type        = bool
  default     = true
}

variable "enable_ipv6" {
  description = "Enable IPv6 support for the VPC"
  type        = bool
  default     = false
}

variable "enable_flow_logs" {
  description = "Enable VPC Flow Logs"
  type        = bool
  default     = true
}

variable "flow_logs_destination_type" {
  description = "Type of flow logs destination (cloud-watch-logs or s3)"
  type        = string
  default     = "cloud-watch-logs"

  validation {
    condition     = contains(["cloud-watch-logs", "s3"], var.flow_logs_destination_type)
    error_message = "Flow logs destination type must be either 'cloud-watch-logs' or 's3'."
  }
}

variable "flow_logs_retention_days" {
  description = "Retention period for flow logs in CloudWatch Logs (days)"
  type        = number
  default     = 30

  validation {
    condition     = contains([0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.flow_logs_retention_days)
    error_message = "Flow logs retention must be a valid CloudWatch Logs retention value."
  }
}

variable "flow_logs_s3_bucket_arn" {
  description = "ARN of S3 bucket for flow logs (required if flow_logs_destination_type is s3)"
  type        = string
  default     = null

  validation {
    condition     = !(var.enable_flow_logs && var.flow_logs_destination_type == "s3") || var.flow_logs_s3_bucket_arn != null
    error_message = "flow_logs_s3_bucket_arn is required when flow logs are sent to s3."
  }
}

variable "enable_vpn_gateway" {
  description = "Enable VPN Gateway for the VPC"
  type        = bool
  default     = false
}

variable "vpn_gateway_amazon_side_asn" {
  description = "ASN for the Amazon side of the VPN Gateway"
  type        = number
  default     = 64512

  validation {
    condition = (
      (var.vpn_gateway_amazon_side_asn >= 64512 && var.vpn_gateway_amazon_side_asn <= 65534) ||
      (var.vpn_gateway_amazon_side_asn >= 4200000000 && var.vpn_gateway_amazon_side_asn <= 4294967294)
    )
    error_message = "VPN gateway Amazon side ASN must be in range 64512-65534 or 4200000000-4294967294."
  }
}

variable "enable_transit_gateway" {
  description = "Enable Transit Gateway attachment"
  type        = bool
  default     = false
}

variable "transit_gateway_id" {
  description = "ID of the Transit Gateway to attach to"
  type        = string
  default     = null

  validation {
    condition     = !var.enable_transit_gateway || var.transit_gateway_id != null
    error_message = "transit_gateway_id is required when enable_transit_gateway is true."
  }
}

variable "transit_gateway_routes" {
  description = "Map of CIDR blocks to route through Transit Gateway (key=cidr, value=tgw)"
  type        = map(string)
  default     = {}
}

variable "enable_vpc_endpoints" {
  description = "Enable VPC endpoints for AWS services"
  type        = bool
  default     = false
}

variable "vpc_endpoints" {
  description = <<-EOT
    Map of VPC endpoint configurations. Each endpoint should specify:
    - service_type: Gateway or Interface
    - route_table_ids: (Gateway only) List of route table IDs or subnet tier names (public, private, database)
    - subnet_ids: (Interface only) List of subnet IDs or subnet tier names (public, private, database)
    - private_dns_enabled: (Interface only) Enable private DNS
    - security_group_ids: (Interface only) List of security group IDs
    - policy: (Optional) IAM policy for the endpoint
  EOT
  type = map(object({
    service_type        = string
    route_table_ids     = optional(list(string), [])
    subnet_ids          = optional(list(string), [])
    private_dns_enabled = optional(bool, true)
    security_group_ids  = optional(list(string))
    policy              = optional(string)
  }))
  default = {}

  validation {
    condition     = alltrue([for e in values(var.vpc_endpoints) : contains(["Gateway", "Interface"], e.service_type)])
    error_message = "vpc_endpoints service_type must be Gateway or Interface."
  }

  validation {
    condition = alltrue([for k in keys(var.vpc_endpoints) : contains([
      "s3", "dynamodb", "ec2", "ec2messages", "ssm", "ssmmessages", "ecr_api", "ecr_dkr", "logs", "kms",
      "secretsmanager", "rds", "sns", "sqs", "lambda", "ecs", "ecs_agent", "ecs_telemetry",
      "elasticloadbalancing", "autoscaling"
    ], k)])
    error_message = "vpc_endpoints keys must be one of the services supported by this module (see local.vpc_endpoint_services)."
  }
}

variable "default_network_acl_ingress" {
  description = "Default network ACL ingress rules"
  type = list(object({
    rule_number = number
    protocol    = string
    rule_action = string
    cidr_block  = string
    from_port   = number
    to_port     = number
  }))
  default = [
    {
      rule_number = 100
      protocol    = "-1"
      rule_action = "allow"
      cidr_block  = "0.0.0.0/0"
      from_port   = 0
      to_port     = 0
    }
  ]
}

variable "default_network_acl_egress" {
  description = "Default network ACL egress rules"
  type = list(object({
    rule_number = number
    protocol    = string
    rule_action = string
    cidr_block  = string
    from_port   = number
    to_port     = number
  }))
  default = [
    {
      rule_number = 100
      protocol    = "-1"
      rule_action = "allow"
      cidr_block  = "0.0.0.0/0"
      from_port   = 0
      to_port     = 0
    }
  ]
}

variable "enable_dhcp_options" {
  description = "Enable custom DHCP options set"
  type        = bool
  default     = false
}

variable "dhcp_options_domain_name" {
  description = "Domain name for DHCP options set"
  type        = string
  default     = null
}

variable "dhcp_options_domain_name_servers" {
  description = "List of domain name servers for DHCP options set"
  type        = list(string)
  default     = ["AmazonProvidedDNS"]
}

variable "manage_default_security_group" {
  description = "Manage the default security group (restrict all traffic by default)"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
