locals {
  security_groups = var.security_groups
}

resource "aws_security_group" "this" {
  for_each = local.security_groups

  name        = "${var.tags["Environment"]}-${each.key}-sg"
  description = lookup(each.value, "description", "Security group for ${each.key}")
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = lookup(each.value, "ingress_rules", [])
    content {
      from_port       = ingress.value.from_port
      to_port         = ingress.value.to_port
      protocol        = ingress.value.protocol
      cidr_blocks     = lookup(ingress.value, "cidr_blocks", null)
      prefix_list_ids = lookup(ingress.value, "prefix_list_ids", null)
      security_groups = lookup(ingress.value, "security_groups", null)
      self            = lookup(ingress.value, "self", null)
      description     = lookup(ingress.value, "description", null)
    }
  }

  dynamic "egress" {
    for_each = lookup(each.value, "egress_rules", [])
    content {
      from_port       = egress.value.from_port
      to_port         = egress.value.to_port
      protocol        = egress.value.protocol
      cidr_blocks     = lookup(egress.value, "cidr_blocks", null)
      prefix_list_ids = lookup(egress.value, "prefix_list_ids", null)
      security_groups = lookup(egress.value, "security_groups", null)
      self            = lookup(egress.value, "self", null)
      description     = lookup(egress.value, "description", null)
    }
  }

  tags = merge(
    var.tags,
    lookup(each.value, "tags", {}),
    {
      Name = "${var.tags["Environment"]}-${each.key}-sg"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}