locals {
  # The readable name. It is the Name tag and the start of the name_prefix
  # below, but not the group's own name -- see the lifecycle comment.
  sg_names = { for k, v in var.security_groups : k => "${var.tags["Environment"]}-${k}-sg" }

  # Every map key resolves to the id of the group this component creates, so a
  # rule can name a sibling group ("alb") instead of an id no stack file can
  # know. Resolved here, in a resource body, and never in a for_each key: a key
  # that depended on this map would be unknown until apply.
  group_ids_by_key = { for k, v in aws_security_group.this : k => v.id }

  # Cloudposse's model, per group instead of per module (one module there is
  # one group; one instance here is a map of them):
  #
  #   preserve_security_group_id = false (default): rules are create-before-
  #     destroy, and any rule change also changes the group's name_prefix
  #     through random_id below, so the new rules land on a NEW group.
  #   preserve_security_group_id = true: the group id survives rule changes,
  #     and rules are destroy-before-create, so a changed rule is briefly
  #     absent.
  #
  # Cloudposse, main.tf: "The only way to guarantee success when creating new
  # rules before destroying old ones is to make the new rules part of a new
  # security group." Most aws_security_group_rule attributes force replacement,
  # so create-before-destroy on the rules alone authorizes the new rule while
  # the old one still holds the same permissions, and AWS rejects the whole
  # call with InvalidPermission.Duplicate
  # (cloudposse/terraform-aws-security-group#34).
  rule_change_forces_new_group = {
    for k, v in var.security_groups : k => !v.preserve_security_group_id
  }
}

# Changes whenever a group's normalized rules change, and feeds the group's
# name_prefix, so a rule change replaces the group. Cloudposse's
# random_id.rule_change_forces_new_security_group, one per group. The keepers
# hold sibling sources by their map key, never a resolved id, so they are
# known at plan.
resource "random_id" "rule_change_forces_new_security_group" {
  for_each = { for k, forced in local.rule_change_forces_new_group : k => k if forced }

  byte_length = 3
  keepers = {
    rules = jsonencode({ for rk, r in local.keyed_rules : rk => r if r.sg_key == each.key })
  }
}

resource "aws_security_group" "this" {
  for_each = local.security_groups

  # name_prefix, not name, because of create_before_destroy below: replacing a
  # group means the new one exists while the old one still does, and two
  # security groups in a VPC cannot share a name. Cloudposse does the same
  # (sg_name_prefix_forced = "<base><delim><random_id.b64_url><delim>"). The
  # readable name lives in the Name tag, which is what the console and every
  # report show.
  name_prefix = (local.rule_change_forces_new_group[each.key]
    ? "${local.sg_names[each.key]}-${random_id.rule_change_forces_new_security_group[each.key].b64_url}-"
  : "${local.sg_names[each.key]}-")

  # coalesce, not lookup: description exists on the typed object and is null
  # when a stack omits it. Handing the provider that null lets AWS write its
  # own default description, and a security group description can only be
  # changed by replacing the group.
  description = coalesce(each.value.description, "Security group for ${each.key}")
  vpc_id      = var.vpc_id

  # No inline ingress/egress blocks. They are authoritative for the group, they
  # cannot reference a sibling group, and the provider removes the default
  # allow-all egress rule when the group carries none -- which is what makes the
  # egress rules below the whole of this group's egress. See normalize.tf.

  tags = merge(
    var.tags,
    each.value.tags,
    {
      Name = local.sg_names[each.key]
    }
  )

  lifecycle {
    # A replacement is created before the original is destroyed. The original
    # cannot be destroyed while an ENI in another component still uses it
    # (DependencyViolation): see "Replacing a group" in the README for the
    # three-step rollout.
    create_before_destroy = true
  }
}

# One resource per rule per source, split across two resources because
# create_before_destroy cannot be set per instance. Everything between the
# lifecycle blocks must stay identical in the two (Cloudposse's
# aws_security_group_rule.keyed and .dbc carry the same warning).
#
# aws_security_group_rule and not aws_vpc_security_group_ingress_rule: this is
# the resource cloudposse/terraform-aws-security-group uses, it takes the CIDR
# and prefix-list sources as lists rather than one resource per prefix, and it
# accepts protocol "-1" with from_port/to_port 0, which the newer pair returns
# as -1 and then diffs against forever. It is marked deprecated in the provider
# documentation and has no announced removal.

# Rules of groups with preserve_security_group_id = false. Their group is new
# whenever they change, so creating first cannot collide with the old rules.
# This is also why positional keys are safe here: removing a middle rule
# renumbers the rest, which changes the keeper, so every rule is created afresh
# on a new, empty group and the old rules go with the old group.
resource "aws_security_group_rule" "keyed" {
  for_each = { for k, r in local.keyed_rules : k => r if local.rule_change_forces_new_group[r.sg_key] }

  lifecycle {
    create_before_destroy = true
  }

  security_group_id = aws_security_group.this[each.value.sg_key].id
  type              = each.value.type
  from_port         = each.value.from_port
  to_port           = each.value.to_port
  protocol          = each.value.protocol
  description       = each.value.description

  # null, not [], for the CIDR lists: an empty list is a rule that authorizes
  # an empty set of prefixes, which the provider sends to AWS as such.
  cidr_blocks      = length(each.value.cidr_blocks) == 0 ? null : each.value.cidr_blocks
  ipv6_cidr_blocks = length(each.value.ipv6_cidr_blocks) == 0 ? null : each.value.ipv6_cidr_blocks
  prefix_list_ids  = each.value.prefix_list_ids

  # A sibling key resolves to that group's id; anything else is already an id.
  # var.security_groups rejects a source that is neither, so this lookup cannot
  # silently pass a typo through as a literal.
  source_security_group_id = each.value.source_security_group_id == null ? null : lookup(
    local.group_ids_by_key,
    each.value.source_security_group_id,
    each.value.source_security_group_id
  )

  # null rather than false: self = false still counts as setting the argument,
  # and it conflicts with cidr_blocks.
  self = each.value.self ? true : null
}

# Rules of groups with preserve_security_group_id = true. The group stays, so a
# changed rule must be revoked before it is re-authorized: a changed rule is
# absent between the two calls. Removing a middle rule replaces every rule
# after it (each index now holds its successor's content) and destroys the
# last index -- Cloudposse's "ripple effect", which an explicit `key` on each
# rule avoids.
resource "aws_security_group_rule" "dbc" {
  for_each = { for k, r in local.keyed_rules : k => r if !local.rule_change_forces_new_group[r.sg_key] }

  lifecycle {
    # No effect beyond emphasis: false is the default.
    create_before_destroy = false
  }

  security_group_id = aws_security_group.this[each.value.sg_key].id
  type              = each.value.type
  from_port         = each.value.from_port
  to_port           = each.value.to_port
  protocol          = each.value.protocol
  description       = each.value.description

  cidr_blocks      = length(each.value.cidr_blocks) == 0 ? null : each.value.cidr_blocks
  ipv6_cidr_blocks = length(each.value.ipv6_cidr_blocks) == 0 ? null : each.value.ipv6_cidr_blocks
  prefix_list_ids  = each.value.prefix_list_ids

  source_security_group_id = each.value.source_security_group_id == null ? null : lookup(
    local.group_ids_by_key,
    each.value.source_security_group_id,
    each.value.source_security_group_id
  )

  self = each.value.self ? true : null
}

# Cloudposse's null_resource.sync_rules_and_sg_lifecycles, one per group whose
# rules are create_before_destroy (their count condition: enabled &&
# rule_create_before_destroy). Their comment, rewrapped:
#
#   This null resource prevents an outage when a new Security Group needs to be
#   provisioned and `local.rule_create_before_destroy` is `true`:
#   1. It prevents the deposed security group rules from being deleted until
#      after all references to it have been changed to refer to the new
#      security group.
#   2. It ensures the new security group rules are created before the new
#      security group is associated with existing resources
#
# Both effects are ordering within this plan. The associations in (1) and (2)
# belong to consumers in other components, which this plan cannot order; what
# remains is that a replaced group's id change replaces this resource, and the
# deposed rules are destroyed only after it -- that is, after every new rule
# exists. See "Replacing a group" in the README.
resource "null_resource" "sync_rules_and_sg_lifecycles" {
  # NOTE (Cloudposse): This resource affects the lifecycles even when count = 0,
  # see https://github.com/hashicorp/terraform/issues/31316#issuecomment-1167450615
  for_each = { for k, forced in local.rule_change_forces_new_group : k => k if forced }

  # Replacement of the security group requires re-provisioning
  triggers = {
    sg_ids = aws_security_group.this[each.key].id
  }

  depends_on = [aws_security_group_rule.keyed]

  lifecycle {
    create_before_destroy = true
  }
}
