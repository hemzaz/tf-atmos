variable "region" {
  type        = string
  description = "AWS region"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-\\d+$", var.region))
    error_message = "The region must be a valid AWS region name (e.g., us-east-1, eu-west-1)."
  }
}

variable "vpc_id" {
  type        = string
  description = "VPC ID where security groups will be created"
}

variable "security_groups" {
  # Typed, not map(any): map(any) infers a single element type for the whole
  # map, so two security groups that do not declare the same set of attributes
  # -- one with egress_rules, one without -- are rejected outright with "all
  # map elements must have the same type".
  #
  # Every attribute is optional with the same fallback main.tf used to pass to
  # lookup(), because lookup() on an object returns an attribute that exists
  # even when it is null and only substitutes the default for one that is
  # absent.
  type = map(object({
    description = optional(string)
    ingress_rules = optional(list(object({
      from_port       = number
      to_port         = number
      protocol        = string
      cidr_blocks     = optional(list(string))
      prefix_list_ids = optional(list(string))
      security_groups = optional(list(string))
      self            = optional(bool)
      description     = optional(string)
      # Declared so that a config using it gets the validation's explanation
      # instead of "unexpected attribute". This component has never read it --
      # see the validation below.
      source_security_group_id = optional(string)
    })), [])
    egress_rules = optional(list(object({
      from_port       = number
      to_port         = number
      protocol        = string
      cidr_blocks     = optional(list(string))
      prefix_list_ids = optional(list(string))
      security_groups = optional(list(string))
      self            = optional(bool)
      description     = optional(string)
      # Declared so that a config using it gets the validation's explanation
      # instead of "unexpected attribute". This component has never read it --
      # see the validation below.
      source_security_group_id = optional(string)
    })), [])
    tags = optional(map(string), {})

    # Accepted and ignored: the group is named "<Environment>-<map key>-sg", so
    # that two entries cannot claim the same name.
    name = optional(string)
  }))
  description = "Map of security groups to create"
  default     = {}

  # source_security_group_id appears in catalog/templates/web-application.yaml
  # and batch-processing.yaml, where it names a SIBLING key in this same map.
  # Nothing here has ever read it: the rule reached AWS with no source at all,
  # which AWS rejects at apply with a message that says nothing about the cause.
  #
  # Supporting it needs more than a lookup -- an inline rule block cannot
  # reference aws_security_group.this without a self-reference cycle, so the
  # rules would have to move to separate aws_vpc_security_group_ingress_rule
  # resources.
  #
  # A validation and not a lifecycle precondition: validation is evaluated
  # while the variable is read, before any provider is configured or any
  # resource is walked, so it is reached even in a stack whose plan cannot get
  # past provider auth. It also reports the offending input by position -- the
  # stack file and line -- which a precondition cannot.
  validation {
    condition = alltrue([
      for k, v in var.security_groups :
      alltrue([
        for r in concat(v.ingress_rules, v.egress_rules) :
        r.source_security_group_id == null
      ])
    ])
    error_message = "Security groups ${join(", ", [for k, v in var.security_groups : k if anytrue([for r in concat(v.ingress_rules, v.egress_rules) : r.source_security_group_id != null])])} set source_security_group_id, which this component does not implement. Pass the security group IDs in the rule's `security_groups` list instead."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to resources; must include Environment (used in resource names)"

  validation {
    condition     = trimspace(lookup(var.tags, "Environment", "")) != ""
    error_message = "tags must include a non-empty Environment value."
  }
}

# Security Group Validation and Logging
variable "enable_security_group_logging" {
  type        = bool
  description = "Enable CloudWatch logging for security group changes"
  default     = true
}

variable "enable_security_group_alarms" {
  type        = bool
  description = "Enable CloudWatch alarms for security group violations"
  default     = true
}

variable "enforce_no_public_ingress" {
  type        = bool
  description = "Enforce that no security groups allow ingress from 0.0.0.0/0 (blocks creation)"
  default     = false
}

variable "log_retention_days" {
  type        = number
  description = "Retention period for security group change logs"
  default     = 90

  validation {
    condition     = contains([0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period."
  }
}

variable "security_alarm_actions" {
  type        = list(string)
  description = "List of SNS topic ARNs for security group alarm notifications"
  default     = []
}