# Rule normalization, after cloudposse/terraform-aws-security-group normalize.tf.
#
# Rules are separate resources, not inline ingress/egress blocks on
# aws_security_group. Two reasons, in order of weight:
#
#   1. An inline block cannot reference aws_security_group.this -- that is a
#      self-reference cycle -- so a rule whose source is a sibling group in this
#      same map is unexpressible. That is exactly what
#      stacks/catalog/templates/web-application.yaml asks for ("the application
#      tier accepts from the alb group").
#   2. Inline blocks are authoritative for the whole group, so any rule change
#      is an update to the group itself. Cloudposse's README is blunt about it:
#      "Setting `inline_rules_enabled` is not recommended and NOT SUPPORTED".
#
# Keys are Cloudposse's: the rule's explicit `key` if it has one, otherwise its
# position in its list (`key = coalesce(lookup(rule, "key", null),
# "${k}[${i}]")`, where k names the list). Here a list is one group's
# ingress_rules or egress_rules, so the positional key is "<type>[<i>]", and
# every key is prefixed with the group's map key because one instance manages
# several groups where one Cloudposse module manages one.
#
# Each rule then splits the way Cloudposse splits a rule_matrix entry, because
# aws_security_group_rule takes one kind of source per resource: "#cidr" for
# the CIDR and prefix-list sources, "#self", and "#sg#<i>" per source group
# (Cloudposse: "${rule.key}#sg", exploded to "${rule.key}#${i}").
# source_security_group_id is appended to the security_groups list for that
# split.
#
# Positional keys renumber when a rule is removed from the middle of a list.
# Cloudposse's README: "If you are using 'create before destroy' behavior for
# the security group and security group rules, then ... keys do not matter".
# See main.tf for how each preserve_security_group_id setting handles it.
#
# for_each needs keys known at plan, so a key never contains a resolved group
# id; resolution of sibling sources happens in the resource body in main.tf.

locals {
  security_groups = var.security_groups

  # Cloudposse main.tf: default_rule_description = "Managed by Terraform",
  # applied in normalize.tf as lookup(rule, "description", <default>). On a
  # typed object the attribute is always present (null when unset), so lookup
  # would return the null; coalesce is what gives their behavior here.
  default_rule_description = "Managed by Terraform"

  norm_rules = flatten([
    for k, sg in var.security_groups : [
      for type, rules in { ingress = sg.ingress_rules, egress = sg.egress_rules } : [
        for i, rule in rules : {
          sg_key          = k
          type            = type
          key             = "${k}/${coalesce(rule.key, "${type}[${i}]")}"
          rule            = rule
          description     = coalesce(rule.description, local.default_rule_description)
          security_groups = concat(rule.security_groups, rule.source_security_group_id == null ? [] : [rule.source_security_group_id])
        }
      ]
    ]
  ])

  self_rules = [for r in local.norm_rules : {
    key                      = "${r.key}#self"
    sg_key                   = r.sg_key
    type                     = r.type
    from_port                = r.rule.from_port
    to_port                  = r.rule.to_port
    protocol                 = r.rule.protocol
    description              = r.description
    cidr_blocks              = []
    ipv6_cidr_blocks         = []
    prefix_list_ids          = []
    source_security_group_id = null
    self                     = true
  } if r.rule.self]

  other_rules = [for r in local.norm_rules : {
    key                      = "${r.key}#cidr"
    sg_key                   = r.sg_key
    type                     = r.type
    from_port                = r.rule.from_port
    to_port                  = r.rule.to_port
    protocol                 = r.rule.protocol
    description              = r.description
    cidr_blocks              = r.rule.cidr_blocks
    ipv6_cidr_blocks         = r.rule.ipv6_cidr_blocks
    prefix_list_ids          = r.rule.prefix_list_ids
    source_security_group_id = null
    self                     = false
  } if length(r.rule.cidr_blocks) + length(r.rule.ipv6_cidr_blocks) + length(r.rule.prefix_list_ids) > 0]

  sg_exploded_rules = flatten([for r in local.norm_rules : [for i, s in r.security_groups : {
    key                      = "${r.key}#sg#${i}"
    sg_key                   = r.sg_key
    type                     = r.type
    from_port                = r.rule.from_port
    to_port                  = r.rule.to_port
    protocol                 = r.rule.protocol
    description              = r.description
    cidr_blocks              = []
    ipv6_cidr_blocks         = []
    prefix_list_ids          = []
    source_security_group_id = s
    self                     = false
  }]])

  # Cloudposse normalize.tf allow_egress_rule / extra_rules, per group. Their
  # allow_all_egress defaults to true; here it defaults to false (see
  # variables.tf and the README). The rule joins all_resource_rules like any
  # other, so it takes the keyed/dbc path and feeds the random_id keepers.
  extra_rules = [for k, sg in var.security_groups : {
    key                      = "${k}/_allow_all_egress_"
    sg_key                   = k
    type                     = "egress"
    from_port                = 0
    to_port                  = 0 # [sic] from and to port ignored when protocol is "-1", warning if not zero
    protocol                 = "-1"
    description              = "Allow all egress"
    cidr_blocks              = ["0.0.0.0/0"]
    ipv6_cidr_blocks         = ["::/0"]
    prefix_list_ids          = []
    source_security_group_id = null
    self                     = false
  } if sg.allow_all_egress]

  all_resource_rules = concat(local.self_rules, local.sg_exploded_rules, local.other_rules, local.extra_rules)
  keyed_rules        = { for r in local.all_resource_rules : r.key => r }
}
