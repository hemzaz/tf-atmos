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
  # Every list is optional with a [] default rather than a bare optional(): a
  # bare optional leaves the attribute present and null, and null is not a list
  # -- length() and contains() both fail on it, which is how the permissive-rule
  # detector in audit.tf used to crash on the first rule that named a source
  # security group instead of a CIDR.
  type = map(object({
    description = optional(string)
    ingress_rules = optional(list(object({
      from_port        = number
      to_port          = number
      protocol         = string
      cidr_blocks      = optional(list(string), [])
      ipv6_cidr_blocks = optional(list(string), [])
      prefix_list_ids  = optional(list(string), [])
      # Sources given as security groups: either an id, or the key of another
      # group in this same map. `security_groups` is a list, so one rule can
      # name several; `source_security_group_id` is the singular spelling the
      # catalog templates and the AWS provider both use. Both are accepted and
      # both resolve the same way.
      security_groups          = optional(list(string), [])
      source_security_group_id = optional(string)
      self                     = optional(bool, false)
      description              = optional(string)
      # Cloudposse's optional rule key: unique within the group, known at
      # plan. Without one the rule is keyed by its position in the list, so
      # removing an earlier rule renumbers it (see normalize.tf and main.tf).
      key = optional(string)
    })), [])
    egress_rules = optional(list(object({
      from_port                = number
      to_port                  = number
      protocol                 = string
      cidr_blocks              = optional(list(string), [])
      ipv6_cidr_blocks         = optional(list(string), [])
      prefix_list_ids          = optional(list(string), [])
      security_groups          = optional(list(string), [])
      source_security_group_id = optional(string)
      self                     = optional(bool, false)
      description              = optional(string)
      key                      = optional(string)
    })), [])
    tags = optional(map(string), {})

    # Cloudposse's preserve_security_group_id, per group. false: any rule
    # change creates a new group (new id) with the new rules; every consumer
    # must follow the new id, and the old group's rules are revoked in the same
    # apply, before the consumers (other components) have moved. true: the id
    # survives rule changes, but a changed rule is revoked before it is
    # re-authorized, so it is briefly absent. Either way a change to
    # description or VPC still replaces the group. See "Replacing a group" in
    # the README.
    preserve_security_group_id = optional(bool, false)

    # Not a setting: rejected by the validation below. It exists in the type
    # only so that a stack still setting it fails loudly -- an attribute
    # missing from an object type is silently dropped, not reported.
    name = optional(string)
  }))
  description = "Map of security groups to create"
  default     = {}

  # Group names are generated -- "<Environment>-<key>-sg-<suffix>" via
  # name_prefix -- so that a replacement group can exist next to the one it
  # replaces. A per-group name would either be ignored or break replacement
  # with InvalidGroup.Duplicate; say so instead of doing either.
  validation {
    condition     = alltrue([for k, v in var.security_groups : v.name == null])
    error_message = "security_groups.<key>.name is not supported (set on: ${join(", ", [for k, v in var.security_groups : k if v.name != null])}). Groups are created with name_prefix \"<Environment>-<key>-sg-\" and AWS appends a unique suffix, so replacements can coexist with the group they replace. Rename the map key to change the name; the readable name is also the Name tag."
  }

  # A map key is resolvable as a rule source, so it must not be mistakable for
  # an AWS security group id. This keeps the resolution in main.tf total: a
  # source that is a key of this map is that group, anything else is an id.
  validation {
    condition     = alltrue([for k, v in var.security_groups : !can(regex("^sg-", k))])
    error_message = "Security group keys must not start with \"sg-\": ${join(", ", [for k, v in var.security_groups : k if can(regex("^sg-", k))])}. The key is how other rules refer to the group, and a key shaped like an id cannot be told apart from one."
  }

  # source_security_group_id and security_groups both name a source. Either the
  # source is a sibling key in this map -- which is how
  # stacks/catalog/templates/web-application.yaml uses it -- or it is a literal
  # id. Anything else is a typo that AWS would only reject at apply, with a
  # message that names neither the group nor the stack file.
  validation {
    condition = alltrue(flatten([
      for k, v in var.security_groups : [
        for r in concat(v.ingress_rules, v.egress_rules) : [
          for s in concat(r.security_groups, r.source_security_group_id == null ? [] : [r.source_security_group_id]) :
          contains(keys(var.security_groups), s) || can(regex("^sg-[0-9a-f]+$", s))
        ]
      ]
    ]))
    error_message = "Every rule source must be either a key of this map (${join(", ", keys(var.security_groups))}) or a security group id matching sg-<hex>. Unresolvable: ${join(", ", distinct(flatten([for k, v in var.security_groups : [for r in concat(v.ingress_rules, v.egress_rules) : [for s in concat(r.security_groups, r.source_security_group_id == null ? [] : [r.source_security_group_id]) : "${k} -> ${s}" if !contains(keys(var.security_groups), s) && !can(regex("^sg-[0-9a-f]+$", s))]]])))}."
  }

  # A rule with no source authorizes nothing. The provider accepts it and AWS
  # rejects it at apply, so catch it here, where the offending stack file and
  # line are still known.
  validation {
    condition = alltrue(flatten([
      for k, v in var.security_groups : [
        for r in concat(v.ingress_rules, v.egress_rules) :
        length(r.cidr_blocks) + length(r.ipv6_cidr_blocks) + length(r.prefix_list_ids) + length(r.security_groups) +
        (r.source_security_group_id == null ? 0 : 1) + (r.self ? 1 : 0) > 0
      ]
    ]))
    error_message = "Every rule needs at least one source: cidr_blocks, ipv6_cidr_blocks, prefix_list_ids, security_groups, source_security_group_id or self. Rules without one in: ${join(", ", [for k, v in var.security_groups : k if anytrue([for r in concat(v.ingress_rules, v.egress_rules) : length(r.cidr_blocks) + length(r.ipv6_cidr_blocks) + length(r.prefix_list_ids) + length(r.security_groups) + (r.source_security_group_id == null ? 0 : 1) + (r.self ? 1 : 0) == 0])])}."
  }

  # cidr_blocks and ipv6_cidr_blocks reach two different provider arguments, so
  # an IPv6 prefix in cidr_blocks is not an address family the rule silently
  # widens -- it is an apply-time error. Split them here instead.
  validation {
    condition = alltrue(flatten([
      for k, v in var.security_groups : [
        for r in concat(v.ingress_rules, v.egress_rules) : concat(
          [for c in r.cidr_blocks : !strcontains(c, ":")],
          [for c in r.ipv6_cidr_blocks : strcontains(c, ":")],
        )
      ]
    ]))
    error_message = "cidr_blocks takes IPv4 prefixes and ipv6_cidr_blocks takes IPv6 prefixes; neither accepts the other."
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
  description = "Enforce that no security groups allow ingress from 0.0.0.0/0 or ::/0 (blocks creation)"
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
