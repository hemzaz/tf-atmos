locals {
  instances = {
    for k, v in var.instances : k => v if lookup(v, "enabled", true)
  }
}

resource "aws_instance" "instances" {
  for_each = local.instances

  ami                    = lookup(each.value, "ami_id", var.default_ami_id)
  instance_type          = each.value.instance_type
  key_name               = lookup(each.value, "key_name", var.default_key_name)
  vpc_security_group_ids = concat([aws_security_group.instances[each.key].id], lookup(each.value, "additional_security_group_ids", []))
  subnet_id              = lookup(each.value, "subnet_id", var.subnet_ids[0])
  user_data              = lookup(each.value, "user_data", null)
  iam_instance_profile   = aws_iam_instance_profile.instances[each.key].name
  monitoring             = lookup(each.value, "detailed_monitoring", false)
  ebs_optimized          = lookup(each.value, "ebs_optimized", true)

  root_block_device {
    volume_type           = lookup(each.value, "root_volume_type", "gp3")
    volume_size           = lookup(each.value, "root_volume_size", 20)
    delete_on_termination = lookup(each.value, "root_volume_delete_on_termination", true)
    encrypted             = lookup(each.value, "root_volume_encrypted", true)
    kms_key_id            = lookup(each.value, "root_volume_kms_key_id", null)
  }

  dynamic "ebs_block_device" {
    for_each = lookup(each.value, "ebs_block_devices", [])
    content {
      device_name           = ebs_block_device.value.device_name
      volume_type           = lookup(ebs_block_device.value, "volume_type", "gp3")
      volume_size           = ebs_block_device.value.volume_size
      iops                  = lookup(ebs_block_device.value, "iops", null)
      throughput            = lookup(ebs_block_device.value, "throughput", null)
      delete_on_termination = lookup(ebs_block_device.value, "delete_on_termination", true)
      encrypted             = lookup(ebs_block_device.value, "encrypted", true)
      kms_key_id            = lookup(ebs_block_device.value, "kms_key_id", null)
    }
  }

  tags = merge(
    var.tags,
    lookup(each.value, "tags", {}),
    {
      Name = "${var.tags["Environment"]}-${each.key}"
    }
  )

  lifecycle {
    ignore_changes = [ami]
  }
}

resource "aws_security_group" "instances" {
  for_each    = local.instances
  name        = "${var.tags["Environment"]}-${each.key}-sg"
  description = "Security group for ${each.key} EC2 instance"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = lookup(each.value, "allowed_ingress_rules", [])
    content {
      from_port       = ingress.value.from_port
      to_port         = ingress.value.to_port
      protocol        = ingress.value.protocol
      cidr_blocks     = lookup(ingress.value, "cidr_blocks", null)
      security_groups = lookup(ingress.value, "security_groups", null)
      description     = lookup(ingress.value, "description", null)
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = merge(
    var.tags,
    lookup(each.value, "tags", {}),
    {
      Name = "${var.tags["Environment"]}-${each.key}-sg"
    }
  )
}

resource "aws_iam_role" "instances" {
  for_each = local.instances
  name     = "${var.tags["Environment"]}-${each.key}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    var.tags,
    lookup(each.value, "tags", {}),
    {
      Name = "${var.tags["Environment"]}-${each.key}-role"
    }
  )
}

resource "aws_iam_instance_profile" "instances" {
  for_each = local.instances
  name     = "${var.tags["Environment"]}-${each.key}-profile"
  role     = aws_iam_role.instances[each.key].name

  tags = merge(
    var.tags,
    lookup(each.value, "tags", {}),
    {
      Name = "${var.tags["Environment"]}-${each.key}-profile"
    }
  )
}

resource "aws_iam_role_policy_attachment" "ssm" {
  for_each   = { for k, v in local.instances : k => v if lookup(v, "enable_ssm", true) }
  role       = aws_iam_role.instances[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "custom" {
  for_each = { for k, v in local.instances : k => v if lookup(v, "custom_iam_policy", "") != "" }
  name     = "${var.tags["Environment"]}-${each.key}-custom-policy"
  role     = aws_iam_role.instances[each.key].id
  policy   = each.value.custom_iam_policy
}

data "aws_ami" "default" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}
