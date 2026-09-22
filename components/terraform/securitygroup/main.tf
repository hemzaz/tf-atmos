locals {
  # The readable name. It is the Name tag and the name_prefix below, but not
  # the group's own name -- see the lifecycle comment.
  sg_names = { for k, v in var.security_groups : k => "${var.tags["Environment"]}-${k}-sg" }

  # Every map key resolves to the id of the group this component creates, so a
  # rule can name a sibling group ("alb") instead of an id no stack file can
  # know. Resolved here, in a resource body, and never in a for_each key: a key
  # that depended on this map would be unknown until apply.
  group_ids_by_key = { for k, v in aws_security_group.this : k => v.id }
}

resource "aws_security_group" "this" {
  for_each = local.security_groups

  # name_prefix, not name, because of create_before_destroy below: replacing a
  # group means the new one exists while the old one still does, and two
  # security groups in a VPC cannot share a name. Cloudposse does the same
  # (`format("%s%s", local.sg_name, var.delimiter)`). The readable name lives in
  # the Name tag, which is what the console and every report show.
  name_prefix = "${local.sg_names[each.key]}-"

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
    # A change that replaces the group -- its description, its VPC -- creates
    # the replacement before tearing down the original, so the ENIs attached to
    # it are never left pointing at a group being deleted. Rule changes no
    # longer replace the group at all; they are their own resources now.
    create_before_destroy = true
  }
}

# One resource per rule per source. Separate rules, not inline blocks: see the
# header of normalize.tf for why, and for how the keys are built.
#
# aws_security_group_rule and not aws_vpc_security_group_ingress_rule: this is
# the resource cloudposse/terraform-aws-security-group uses, it takes the CIDR
# and prefix-list sources as lists rather than one resource per prefix, and it
# accepts protocol "-1" with from_port/to_port 0, which the newer pair returns
# as -1 and then diffs against forever. It is marked deprecated in the provider
# documentation and has no announced removal.
resource "aws_security_group_rule" "this" {
  for_each = local.keyed_rules

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

  lifecycle {
    # Matches the group's own create_before_destroy, so a replaced group gets
    # its new rules before the old rules and the old group are removed.
    create_before_destroy = true
  }
}
