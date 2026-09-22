# Rule normalization, after cloudposse/terraform-aws-security-group.
#
# Rules are separate resources, not inline ingress/egress blocks on
# aws_security_group. Two reasons, in order of weight:
#
#   1. An inline block cannot reference aws_security_group.this -- that is a
#      self-reference cycle -- so a rule whose source is a sibling group in this
#      same map is unexpressible. That is exactly what
#      stacks/catalog/templates/web-application.yaml asks for ("the application
#      tier accepts from the alb group"), and what this component used to drop
#      on the floor.
#   2. Inline blocks are authoritative for the whole group, so any rule change
#      is an update to the group itself. Cloudposse's README is blunt about it:
#      "Setting `inline_rules_enabled` is not recommended and NOT SUPPORTED".
#
# Keys. for_each needs a key that is known at plan, so a key never contains a
# resolved group id; a sibling source appears in it by its map key. Where a rule
# carries no `key`, the key is derived from what the rule authorizes rather than
# from its position in the list:
#
#   <group>/<direction>/<protocol>:<from>-<to>#cidr        the CIDR/prefix-list sources
#   <group>/<direction>/<protocol>:<from>-<to>#sg:<source> one per source group
#   <group>/<direction>/<protocol>:<from>-<to>#self        self
#
# This departs from Cloudposse, whose default key is the list position
# ("${k}[${i}]"). Their README calls the consequence "the unwelcome behavior
# that removing a rule from the list will cause all the rules later in the list
# to be destroyed and recreated" and leaves it to the caller to add keys. With a
# content key, removing a rule destroys that rule and nothing else.
#
# Why the CIDRs are NOT in the key. An AWS permission is (protocol, ports,
# source), and AWS rejects an authorize call that repeats one that exists
# (InvalidPermission.Duplicate). Terraform gives no ordering between destroying
# one for_each instance and creating another, so a key that changed whenever a
# CIDR was added would destroy the old rule and create the new one concurrently
# -- and the CIDRs the two share would be authorized twice. With the CIDRs out of
# the key, a CIDR change replaces the same instance, and a replacement of one
# instance is ordered. The rule that holds for every derived key: no AWS
# permission can move from one Terraform instance to another.
#
# The price: two CIDR rules in one group and direction with the same protocol
# and ports would share a key. main.tf rejects that at plan (merge their CIDR
# lists, or give them distinct `key`s). An explicit `key` restores the
# Cloudposse behavior for that rule: its identity is whatever the caller says.

locals {
  security_groups = var.security_groups

  # One entry per rule as written, carrying where it came from. The map literal
  # below is iterated in key order, so egress sorts before ingress; the
  # direction is part of the key, so the order does not affect identity.
  rule_list = flatten([
    for k, sg in var.security_groups : [
      for type, rules in { ingress = sg.ingress_rules, egress = sg.egress_rules } : [
        for rule in rules : {
          sg_key = k
          type   = type
          base_key = (rule.key != null
            ? "${k}/${type}[${rule.key}]"
          : "${k}/${type}/${lower(rule.protocol)}:${rule.from_port}-${rule.to_port}")
          rule = rule
          # security_groups and source_security_group_id are two spellings of the
          # same thing; naming a group in both is one AWS permission, not two.
          sg_sources = distinct(concat(
            rule.security_groups,
            rule.source_security_group_id == null ? [] : [rule.source_security_group_id],
          ))
        }
      ]
    ]
  ])

  # One entry per rule *resource*. aws_security_group_rule takes the CIDR and
  # prefix-list sources as lists, so those stay in one rule; a security group
  # source and `self` are singular and mutually exclusive with them, so each
  # gets its own.
  expanded_rules = flatten([
    for r in local.rule_list : concat(
      (length(r.rule.cidr_blocks) + length(r.rule.ipv6_cidr_blocks) + length(r.rule.prefix_list_ids)) == 0 ? [] : [{
        key                      = "${r.base_key}#cidr"
        sg_key                   = r.sg_key
        type                     = r.type
        from_port                = r.rule.from_port
        to_port                  = r.rule.to_port
        protocol                 = r.rule.protocol
        description              = r.rule.description
        cidr_blocks              = r.rule.cidr_blocks
        ipv6_cidr_blocks         = r.rule.ipv6_cidr_blocks
        prefix_list_ids          = r.rule.prefix_list_ids
        source_security_group_id = null
        self                     = false
      }],
      [for s in r.sg_sources : {
        key                      = "${r.base_key}#sg:${s}"
        sg_key                   = r.sg_key
        type                     = r.type
        from_port                = r.rule.from_port
        to_port                  = r.rule.to_port
        protocol                 = r.rule.protocol
        description              = r.rule.description
        cidr_blocks              = []
        ipv6_cidr_blocks         = []
        prefix_list_ids          = []
        source_security_group_id = s
        self                     = false
      }],
      !r.rule.self ? [] : [{
        key                      = "${r.base_key}#self"
        sg_key                   = r.sg_key
        type                     = r.type
        from_port                = r.rule.from_port
        to_port                  = r.rule.to_port
        protocol                 = r.rule.protocol
        description              = r.rule.description
        cidr_blocks              = []
        ipv6_cidr_blocks         = []
        prefix_list_ids          = []
        source_security_group_id = null
        self                     = true
      }],
    )
  ])

  # Grouped first, so that two rules claiming one key surface as a named
  # precondition failure in main.tf instead of Terraform's bare "Duplicate
  # object key".
  rules_by_key        = { for r in local.expanded_rules : r.key => r... }
  duplicate_rule_keys = [for k, rs in local.rules_by_key : k if length(rs) > 1]

  # What for_each consumes.
  keyed_rules = { for k, rs in local.rules_by_key : k => rs[0] }
}
