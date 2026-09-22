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
# Keys are the part that makes separate rules safe. for_each needs a key that is
# stable across plans and that does not depend on a value Terraform only learns
# at apply. Rules are keyed by position, so deleting the second of four rules
# renumbers the two after it -- set `key` on a rule to pin its identity. The
# resolution of a source to a group id happens in main.tf, in the resource
# body, never in a key: a key that depended on aws_security_group.this would
# make the whole map unknown at plan.

locals {
  security_groups = var.security_groups

  # One entry per rule as written, carrying where it came from. The map literal
  # below is iterated in key order, so egress sorts before ingress; the
  # direction is part of the key, so the order does not affect identity.
  rule_list = flatten([
    for k, sg in var.security_groups : [
      for type, rules in { ingress = sg.ingress_rules, egress = sg.egress_rules } : [
        for i, rule in rules : {
          sg_key   = k
          type     = type
          base_key = "${k}/${type}[${rule.key != null ? rule.key : i}]"
          rule     = rule
        }
      ]
    ]
  ])

  # One entry per rule *resource*. aws_security_group_rule takes the CIDR and
  # prefix-list sources as lists, so those stay in one rule; a security group
  # source and `self` are singular and mutually exclusive with them, so each
  # gets its own. The suffix keeps the split legible in a plan:
  # "app/ingress[0]#sg[1]" is the second source group of the first ingress rule.
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
      [for j, s in r.rule.security_groups : {
        key                      = "${r.base_key}#sg[${j}]"
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
      r.rule.source_security_group_id == null ? [] : [{
        key                      = "${r.base_key}#src"
        sg_key                   = r.sg_key
        type                     = r.type
        from_port                = r.rule.from_port
        to_port                  = r.rule.to_port
        protocol                 = r.rule.protocol
        description              = r.rule.description
        cidr_blocks              = []
        ipv6_cidr_blocks         = []
        prefix_list_ids          = []
        source_security_group_id = r.rule.source_security_group_id
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

  # What for_each consumes. A duplicate key here means two rules claim the same
  # identity, which only an explicit `key` set twice can cause.
  keyed_rules = { for r in local.expanded_rules : r.key => r }
}
