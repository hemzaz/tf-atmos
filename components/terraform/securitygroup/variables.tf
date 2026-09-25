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

    # Cloudposse's allow_all_egress, per group: adds their "_allow_all_egress_"
    # rule (egress, -1, 0.0.0.0/0 and ::/0). Defaults to true, matching
    # Cloudposse: this repo's "never 0.0.0.0/0 or ::/0" rule governs INGRESS
    # only (what the outside can reach inside, see enforce_no_public_ingress
    # below and audit.tf); outbound is unrestricted by policy. See the README.
    allow_all_egress = optional(bool, true)

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

  # Rule keys are "<group>/<key or type[i]>" plus "#cidr", "#self" or "#sg#<i>"
  # (normalize.tf). "/" or "#" in a group key would let two different
  # (group, rule) pairs spell the same resource key.
  validation {
    condition     = alltrue([for k, v in var.security_groups : !can(regex("[/#]", k))])
    error_message = "Security group keys must not contain \"/\" or \"#\": ${join(", ", [for k, v in var.security_groups : k if can(regex("[/#]", k))])}. They are separators in the rule keys."
  }

  # An explicit rule key shares the namespace of the positional keys
  # ("ingress[0]") and the reserved "_allow_all_egress_". The character set
  # excludes brackets, so no explicit key can look positional.
  validation {
    condition = alltrue(flatten([
      for k, v in var.security_groups : [
        for r in concat(v.ingress_rules, v.egress_rules) :
        r.key == null ? true : (can(regex("^[A-Za-z0-9_.-]+$", r.key)) && r.key != "_allow_all_egress_")
      ]
    ]))
    error_message = "Rule keys must match ^[A-Za-z0-9_.-]+$ and must not be \"_allow_all_egress_\" (reserved for allow_all_egress). A key like \"ingress[0]\" would collide with the positional key of an unkeyed rule. Offending: ${join(", ", distinct(flatten([for k, v in var.security_groups : [for r in concat(v.ingress_rules, v.egress_rules) : "${k}: ${r.key}" if r.key != null && (!can(regex("^[A-Za-z0-9_.-]+$", coalesce(r.key, "x"))) || r.key == "_allow_all_egress_")]])))}."
  }

  # A group naming itself as a source is `self: true` under another spelling:
  # the same AWS permission, keyed differently, so setting both fails at apply
  # as a duplicate, and switching between them races two instances.
  validation {
    condition = alltrue(flatten([
      for k, v in var.security_groups : [
        for r in concat(v.ingress_rules, v.egress_rules) :
        !contains(concat(r.security_groups, r.source_security_group_id == null ? [] : [r.source_security_group_id]), k)
      ]
    ]))
    error_message = "A rule must not name its own group as a source; use `self: true`. Offending groups: ${join(", ", [for k, v in var.security_groups : k if anytrue([for r in concat(v.ingress_rules, v.egress_rules) : contains(concat(r.security_groups, r.source_security_group_id == null ? [] : [r.source_security_group_id]), k)])])}."
  }

  # source_security_group_id and security_groups both name a source. The
  # source is either a sibling key in this map, or a literal sg-<hex> id read
  # from another component via !terraform.state -- see
  # stacks/catalog/templates/web-application.yaml's "http-from-alb" rule,
  # which reads web-application/alb's security_group_id output this way.
  # Anything else is a typo that AWS would only reject at apply, with a
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

  # "6" and "tcp", or "all" and "-1", are one AWS permission under two
  # spellings. Two rules differing only in the spelling pass plan and fail at
  # apply with InvalidPermission.Duplicate, and changing the spelling alone
  # replaces the rule. Cloudposse passes protocol through unnormalized
  # (normalize.tf: `protocol = rule.protocol`), so accept one spelling rather
  # than rewrite it: the canonical lower-case name where AWS has one, "-1" for
  # all protocols, and the number for anything else.
  validation {
    condition = alltrue(flatten([
      for k, v in var.security_groups : [
        for r in concat(v.ingress_rules, v.egress_rules) :
        !contains(["6", "17", "1", "58", "all"], lower(r.protocol)) && r.protocol == lower(r.protocol)
      ]
    ]))
    error_message = "protocol must be spelled \"tcp\", \"udp\", \"icmp\", \"icmpv6\", \"-1\" (all), or a number for any other protocol -- not \"6\", \"17\", \"1\", \"58\", \"all\", or upper case. Offending: ${join(", ", distinct(flatten([for k, v in var.security_groups : [for r in concat(v.ingress_rules, v.egress_rules) : "${k}: ${r.protocol}" if contains(["6", "17", "1", "58", "all"], lower(r.protocol)) || r.protocol != lower(r.protocol)]])))}."
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
  default     = true
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
