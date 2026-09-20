variable "region" {
  type        = string
  description = "AWS region"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-\\d+$", var.region))
    error_message = "The region must be a valid AWS region name (e.g., us-east-1, eu-west-1)."
  }
}

variable "name_prefix" {
  type        = string
  description = "Prefix for resource names. Stacks set this to tenant-account-environment"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*$", var.name_prefix))
    error_message = "The name_prefix must be lowercase alphanumeric with hyphens."
  }
}

variable "enabled" {
  type        = bool
  description = "Set to false to prevent the component from creating any resources"
  default     = true
}

# Required on purpose: a `default = {}` here makes every resource look untagged to
# tflint/checkov, which run per-component without stack vars. Keep it required.
variable "tags" {
  type        = map(string)
  description = "Tags to apply to resources; must include Environment (used in resource names)"

  validation {
    condition     = trimspace(lookup(var.tags, "Environment", "")) != ""
    error_message = "tags must include a non-empty Environment value."
  }
}

variable "create_vpc_peering" {
  type        = bool
  description = "Create the peering connection and its routes"
  default     = true
}

variable "requester_vpc_id" {
  type        = string
  description = "VPC that initiates the peering connection"
  default     = ""

  validation {
    condition     = var.requester_vpc_id == "" || can(regex("^vpc-[0-9a-f]{8,17}$", var.requester_vpc_id))
    error_message = "The requester_vpc_id must be a VPC id such as vpc-0a1b2c3d4e5f6a7b8."
  }
}

variable "accepter_vpc_id" {
  type        = string
  description = "VPC that accepts the peering connection"
  default     = ""

  validation {
    condition     = var.accepter_vpc_id == "" || can(regex("^vpc-[0-9a-f]{8,17}$", var.accepter_vpc_id))
    error_message = "The accepter_vpc_id must be a VPC id such as vpc-0a1b2c3d4e5f6a7b8."
  }
}

variable "auto_accept" {
  type        = bool
  description = "Accept the peering connection automatically. Only works when both VPCs are in the same account and region"
  default     = true
}

# Routes carry the route table ids explicitly rather than having this component
# look them up, so the stack's !terraform.state reference makes the vpc -> network
# dependency visible to check-dependencies.py.
variable "requester_routes" {
  type = list(object({
    destination_cidr_block = string
    route_table_ids        = list(string)
  }))
  description = "Routes added to the requester VPC's route tables, pointing at the peer's CIDR"
  default     = []
}

variable "accepter_routes" {
  type = list(object({
    destination_cidr_block = string
    route_table_ids        = list(string)
  }))
  description = "Routes added to the accepter VPC's route tables, pointing at the peer's CIDR"
  default     = []
}
