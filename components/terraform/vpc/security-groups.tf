resource "aws_security_group" "default" {
  name        = "${var.tags["Environment"]}-default-sg"
  description = "Default security group to allow inbound/outbound from the VPC"
  vpc_id      = aws_vpc.main.id

  # Allow all communication within the security group
  dynamic "ingress" {
    for_each = var.default_sg_ingress_self_only ? [1] : []
    content {
      from_port = "0"
      to_port   = "0"
      protocol  = "-1"
      self      = true
      description = "Allow all inbound traffic within this security group"
    }
  }

  # Add custom ingress rules if provided
  dynamic "ingress" {
    for_each = var.default_security_group_ingress_rules
    content {
      from_port       = ingress.value.from_port
      to_port         = ingress.value.to_port
      protocol        = ingress.value.protocol
      cidr_blocks     = lookup(ingress.value, "cidr_blocks", null)
      security_groups = lookup(ingress.value, "security_groups", null)
      self            = lookup(ingress.value, "self", null)
      description     = lookup(ingress.value, "description", "Custom ingress rule")
    }
  }

  # Allow all outbound to self
  dynamic "egress" {
    for_each = var.default_sg_egress_self_only ? [1] : []
    content {
      from_port = "0"
      to_port   = "0"
      protocol  = "-1"
      self      = true
      description = "Allow all outbound traffic within this security group"
    }
  }

  # Add custom egress rules if provided
  dynamic "egress" {
    for_each = var.default_sg_allow_all_outbound ? [1] : []
    content {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
      description = "Allow all outbound traffic"
    }
  }

  # Add custom egress rules if provided
  dynamic "egress" {
    for_each = var.default_security_group_egress_rules
    content {
      from_port       = egress.value.from_port
      to_port         = egress.value.to_port
      protocol        = egress.value.protocol
      cidr_blocks     = lookup(egress.value, "cidr_blocks", null)
      security_groups = lookup(egress.value, "security_groups", null)
      self            = lookup(egress.value, "self", null)
      description     = lookup(egress.value, "description", "Custom egress rule")
    }
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.tags["Environment"]}-default-sg"
    }
  )
}