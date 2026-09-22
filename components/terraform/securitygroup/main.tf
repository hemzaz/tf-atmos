locals {
  security_groups = var.security_groups
}

resource "aws_security_group" "this" {
  for_each = local.security_groups

  name = "${var.tags["Environment"]}-${each.key}-sg"
  # coalesce, not lookup: description exists on the typed object and is null
  # when a stack omits it. Handing the provider that null lets AWS write its
  # own default description, and a security group description can only be
  # changed by replacing the group.
  description = coalesce(each.value.description, "Security group for ${each.key}")
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = each.value.ingress_rules
    content {
      from_port       = ingress.value.from_port
      to_port         = ingress.value.to_port
      protocol        = ingress.value.protocol
      cidr_blocks     = ingress.value.cidr_blocks
      prefix_list_ids = ingress.value.prefix_list_ids
      security_groups = ingress.value.security_groups
      self            = ingress.value.self
      description     = ingress.value.description
    }
  }

  dynamic "egress" {
    for_each = each.value.egress_rules
    content {
      from_port       = egress.value.from_port
      to_port         = egress.value.to_port
      protocol        = egress.value.protocol
      cidr_blocks     = egress.value.cidr_blocks
      prefix_list_ids = egress.value.prefix_list_ids
      security_groups = egress.value.security_groups
      self            = egress.value.self
      description     = egress.value.description
    }
  }

  tags = merge(
    var.tags,
    each.value.tags,
    {
      Name = "${var.tags["Environment"]}-${each.key}-sg"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}
