variable "region" {
  type        = string
  description = "AWS region"
  default     = "eu-west-2"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-\\d+$", var.region))
    error_message = "The region must be a valid AWS region name (e.g., us-east-1, eu-west-1)."
  }
}

# Input names follow cloudposse-terraform-components/aws-vpc wherever an input
# maps one to one (ipv4_primary_cidr_block, availability_zones,
# nat_gateway_enabled, map_public_ip_on_launch, vpc_flow_logs_*).
variable "ipv4_primary_cidr_block" {
  type        = string
  description = "The primary IPv4 CIDR block for the VPC"

  validation {
    condition     = can(cidrhost(var.ipv4_primary_cidr_block, 0))
    error_message = "Must be a valid IPv4 CIDR block address."
  }
}

variable "management_cidr" {
  type        = string
  description = "CIDR block for management access (SSH, etc.). If null, SSH access is disabled"
  default     = null

  validation {
    condition     = var.management_cidr == null || can(cidrhost(var.management_cidr, 0))
    error_message = "Must be a valid IPv4 CIDR block address or null."
  }
}

variable "availability_zones" {
  type        = list(string)
  description = "Availability Zones for the subnets, in subnet order: subnet N goes to availability_zones[N]"

  validation {
    condition     = length(var.availability_zones) > 0
    error_message = "At least one availability zone must be provided."
  }
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

variable "database_subnets" {
  type        = list(string)
  description = "CIDR blocks for database subnets"
  default     = []

  validation {
    condition     = alltrue([for cidr in var.database_subnets : can(cidrhost(cidr, 0))])
    error_message = "All database subnet CIDR blocks must be valid IPv4 CIDR block addresses."
  }
}

variable "nat_gateway_enabled" {
  type        = bool
  description = "Flag to enable/disable NAT gateways"
  default     = true
}

# Cloud Posse defaults this to true. Here it defaults to false: an instance
# launched into a public subnet gets no public IP unless the stack opts in
# (trivy AWS-0164), and nothing in these stacks launches instances that need one.
variable "map_public_ip_on_launch" {
  type        = bool
  description = "Instances launched into a public subnet should be assigned a public IP address"
  default     = false
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

variable "nat_gateway_azs" {
  type        = list(string)
  description = "List of AZs to place NAT gateways in, must match the number of gateways. If not specified, will use available AZs."
  default     = null
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

variable "manage_network_acls" {
  type        = bool
  description = "Manage subnet network ACLs in this component. Set false where NACLs are managed centrally, or when running against an emulator that does not implement them"
  default     = true
}

variable "manage_default_security_group" {
  type        = bool
  description = "Manage the VPC's AWS-created default security group and strip all of its rules. One way: setting this back to false, or destroying the resource, only drops the group from state - the removed rules are not restored"
  default     = true
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
  description = "Tags to apply to resources; must include Environment (used in resource names)"

  validation {
    condition     = trimspace(lookup(var.tags, "Environment", "")) != ""
    error_message = "tags must include a non-empty Environment value."
  }
}

# Extra subnet tags, named as in Cloud Posse's aws-vpc component. EKS and the
# AWS Load Balancer Controller find subnets by these tags
# (kubernetes.io/role/elb, kubernetes.io/role/internal-elb,
# kubernetes.io/cluster/<name>).
variable "public_subnets_additional_tags" {
  type        = map(string)
  description = "Tags added to every public subnet"
  default     = {}

  validation {
    condition     = !contains(keys(var.public_subnets_additional_tags), "Name")
    error_message = "public_subnets_additional_tags must not set Name; the component names each subnet."
  }
}

variable "private_subnets_additional_tags" {
  type        = map(string)
  description = "Tags added to every private subnet"
  default     = {}

  validation {
    condition     = !contains(keys(var.private_subnets_additional_tags), "Name")
    error_message = "private_subnets_additional_tags must not set Name; the component names each subnet."
  }
}

# VPC Flow Logs Variables
variable "vpc_flow_logs_enabled" {
  type        = bool
  description = "Enable or disable the VPC Flow Logs"
  default     = true
}

variable "flow_logs_retention_days" {
  type        = number
  description = "Retention period in days for VPC Flow Logs in CloudWatch"
  default     = 30

  validation {
    condition     = contains([0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.flow_logs_retention_days)
    error_message = "Flow logs retention days must be a valid CloudWatch Logs retention period."
  }
}

variable "vpc_flow_logs_traffic_type" {
  type        = string
  description = "The type of traffic to capture. Valid values: ACCEPT, REJECT, ALL"
  default     = "ALL"

  validation {
    condition     = contains(["ACCEPT", "REJECT", "ALL"], var.vpc_flow_logs_traffic_type)
    error_message = "vpc_flow_logs_traffic_type must be ACCEPT, REJECT or ALL."
  }
}

variable "vpc_flow_logs_max_aggregation_interval" {
  type        = number
  description = "Maximum interval of time during which a flow is captured and aggregated (60 or 600 seconds)"
  default     = 600

  validation {
    condition     = contains([60, 600], var.vpc_flow_logs_max_aggregation_interval)
    error_message = "Flow logs aggregation interval must be either 60 or 600 seconds."
  }
}

variable "vpc_flow_logs_format" {
  type        = string
  description = "The fields to include in the flow log record. If null, uses this component's default format"
  default     = null
}

variable "enable_flow_logs_alarms" {
  type        = bool
  description = "Enable CloudWatch alarms for VPC Flow Logs security events"
  default     = true
}

variable "flow_logs_alarm_actions" {
  type        = list(string)
  description = "List of SNS topic ARNs to notify when Flow Logs alarms trigger"
  default     = []
}

variable "ssh_access_alarm_threshold" {
  type        = number
  description = "Number of SSH access attempts before triggering alarm"
  default     = 50
}

variable "rdp_access_alarm_threshold" {
  type        = number
  description = "Number of RDP access attempts before triggering alarm"
  default     = 50
}

variable "rejected_connections_alarm_threshold" {
  type        = number
  description = "Number of rejected connections before triggering alarm"
  default     = 100
}

variable "large_data_transfer_alarm_threshold" {
  type        = number
  description = "Bytes transferred in 15 minutes before triggering alarm (potential data exfiltration)"
  default     = 1073741824 # 1GB
}

variable "port_scan_alarm_threshold" {
  type        = number
  description = "Number of port scan attempts before triggering alarm"
  default     = 50
}

variable "flow_logs_s3_backup" {
  type        = bool
  description = "Enable S3 bucket for long-term Flow Logs storage and archival"
  default     = false
}