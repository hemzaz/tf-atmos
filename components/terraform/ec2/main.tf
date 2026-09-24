# One EC2 instance per component instance, as in
# cloudposse-terraform-components/aws-ec2-instance: every resource is
# `count = ... ? 1 : 0`, and the outputs are cloudposse/terraform-aws-ec2-instance's.

locals {
  enabled     = var.enabled
  environment = var.tags["Environment"]

  # Every name is "<Environment>-<name>", the repo's name_prefix convention.
  # var.name must not repeat the Environment (see its validation).
  name_prefix = "${local.environment}-${var.name}"

  subnet = try(coalesce(var.subnet, try(var.subnet_ids[0], null)), null)

  ssh_key_pair = var.ssh_key_pair == "" ? null : var.ssh_key_pair
  # A key is generated only when none is given: one per instance, named after
  # it, so two instances in a stack never create the same key or secret.
  generate_key = local.enabled && var.create_ssh_keys && local.ssh_key_pair == null
  key_name     = local.generate_key ? one(aws_key_pair.generated[*].key_name) : local.ssh_key_pair

  ami = var.ami != "" ? var.ami : one(data.aws_ami.default[*].id)

  # Exactly one of aws_instance.default and aws_instance.from_launch_template
  # exists. create_instances_from_templates requires enable_launch_templates
  # (validated), so it alone decides.
  from_template = var.create_instances_from_templates
  # Attribute by attribute: referencing the whole instance object would read
  # its deprecated network_interface attribute.
  instance = {
    id         = one(concat(aws_instance.default[*].id, aws_instance.from_launch_template[*].id))
    private_ip = one(concat(aws_instance.default[*].private_ip, aws_instance.from_launch_template[*].private_ip))
    public_ip  = one(concat(aws_instance.default[*].public_ip, aws_instance.from_launch_template[*].public_ip))
    subnet_id  = one(concat(aws_instance.default[*].subnet_id, aws_instance.from_launch_template[*].subnet_id))
  }

  security_group_ids = concat(aws_security_group.default[*].id, var.security_groups)

  metadata_options = {
    http_endpoint               = "enabled"
    http_tokens                 = var.metadata_http_tokens_required ? "required" : "optional"
    http_put_response_hop_limit = var.metadata_http_put_response_hop_limit
    instance_metadata_tags      = var.metadata_tags_enabled ? "enabled" : "disabled"
  }
}

# Generated key pair, when the instance is given none
resource "tls_private_key" "ssh_key" {
  count = local.generate_key ? 1 : 0

  algorithm = var.ssh_key_algorithm
  rsa_bits  = var.ssh_key_algorithm == "RSA" ? var.ssh_key_rsa_bits : null
}

resource "aws_key_pair" "generated" {
  count = local.generate_key ? 1 : 0

  key_name   = "${local.name_prefix}-ec2-ssh-key"
  public_key = tls_private_key.ssh_key[0].public_key_openssh

  tags = merge(var.tags, { Name = "${local.name_prefix}-ec2-ssh-key" })
}

resource "aws_secretsmanager_secret" "ssh_key" {
  count = local.generate_key && var.store_ssh_keys_in_secrets_manager ? 1 : 0

  name        = "ssh-key/${local.environment}/${var.name}"
  description = "SSH private key for the ${local.name_prefix} EC2 instance"
  kms_key_id  = var.ssh_key_secret_kms_key_id

  # Days a deleted secret stays recoverable (0: delete at once), as
  # recovery_window_in_days in Cloud Posse's secrets-manager.
  recovery_window_in_days = var.ssh_key_secret_recovery_window_in_days

  tags = merge(var.tags, {
    Name         = "${local.name_prefix}-ssh-key"
    InstanceName = local.name_prefix
    KeyType      = "instance"
  })
}

# SSH private keys stay regular (non-ephemeral) values: aws_key_pair.public_key is not a
# write-only argument, so an ephemeral tls_private_key cannot feed it, and the key pair is
# already in state through tls_private_key. secret_string_wo would therefore hide nothing.
resource "aws_secretsmanager_secret_version" "ssh_key" {
  count = local.generate_key && var.store_ssh_keys_in_secrets_manager ? 1 : 0

  secret_id = aws_secretsmanager_secret.ssh_key[0].id
  secret_string = jsonencode({
    private_key_openssh = tls_private_key.ssh_key[0].private_key_openssh
    private_key_pem     = tls_private_key.ssh_key[0].private_key_pem
    public_key_openssh  = tls_private_key.ssh_key[0].public_key_openssh
    key_name            = aws_key_pair.generated[0].key_name
    instance_name       = local.name_prefix
    instance_id         = local.instance.id
    instance_private_ip = local.instance.private_ip
    instance_public_ip  = local.instance.public_ip
    vpc_id              = var.vpc_id
    subnet_id           = local.instance.subnet_id
    security_group_id   = aws_security_group.default[0].id
    environment         = local.environment
  })
}

resource "aws_instance" "default" {
  #checkov:skip=CKV_AWS_79:http_tokens is "required" unless a stack sets metadata_http_tokens_required = false
  count = local.enabled && !local.from_template ? 1 : 0

  ami                         = local.ami
  instance_type               = var.instance_type
  key_name                    = local.key_name
  vpc_security_group_ids      = local.security_group_ids
  subnet_id                   = local.subnet
  associate_public_ip_address = var.associate_public_ip_address
  user_data                   = var.user_data
  iam_instance_profile        = aws_iam_instance_profile.default[0].name
  monitoring                  = var.monitoring
  ebs_optimized               = var.ebs_optimized
  disable_api_termination     = var.disable_api_termination

  root_block_device {
    volume_type           = var.root_volume_type
    volume_size           = var.root_volume_size
    delete_on_termination = var.delete_on_termination
    encrypted             = var.root_block_device_encrypted
    kms_key_id            = var.root_block_device_kms_key_id
  }

  dynamic "ebs_block_device" {
    for_each = var.ebs_block_devices
    content {
      device_name           = ebs_block_device.value.device_name
      volume_type           = ebs_block_device.value.volume_type
      volume_size           = ebs_block_device.value.volume_size
      iops                  = ebs_block_device.value.iops
      throughput            = ebs_block_device.value.throughput
      delete_on_termination = ebs_block_device.value.delete_on_termination
      encrypted             = ebs_block_device.value.encrypted
      kms_key_id            = try(coalesce(ebs_block_device.value.kms_key_id, var.root_block_device_kms_key_id), null)
      snapshot_id           = ebs_block_device.value.snapshot_id
    }
  }

  metadata_options {
    http_endpoint               = local.metadata_options.http_endpoint
    http_tokens                 = local.metadata_options.http_tokens
    http_put_response_hop_limit = local.metadata_options.http_put_response_hop_limit
    instance_metadata_tags      = local.metadata_options.instance_metadata_tags
  }

  tags = merge(var.tags, { Name = local.name_prefix })

  lifecycle {
    # AMI updates never replace instances in place
    ignore_changes = [ami]

    # No key precondition: a keyless instance (ssh_key_pair unset and
    # create_ssh_keys false) is reached through SSM, as Cloud Posse's
    # aws-ec2-instance allows.

    precondition {
      condition     = local.subnet != null
      error_message = "Instance ${local.name_prefix} has no subnet: set subnet or subnet_ids."
    }

    # data.aws_key_pair.existing fails the plan when the named key does not
    # exist; this ties that check to the instance that needs it.
    precondition {
      condition     = local.ssh_key_pair == null || one(data.aws_key_pair.existing[*].key_name) == local.ssh_key_pair
      error_message = "Instance ${local.name_prefix} references a key pair (ssh_key_pair) that does not exist in AWS."
    }
  }
}

#trivy:ignore:AVD-AWS-0104 Egress is unrestricted by policy (owner decision): the repo's 0.0.0.0/0 rule covers inbound traffic only, and all-outbound is Cloud Posse aws-ec2-instance's default. Ingress rejects any /0 (variable validation).
resource "aws_security_group" "default" {
  #checkov:skip=CKV2_AWS_5:Attached to the instance (vpc_security_group_ids) or its launch template; checkov's graph does not follow count-indexed references through locals
  count = local.enabled ? 1 : 0

  name        = "${local.name_prefix}-sg"
  description = "Security group for the ${local.name_prefix} EC2 instance"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = var.allowed_ingress_rules
    content {
      from_port       = ingress.value.from_port
      to_port         = ingress.value.to_port
      protocol        = ingress.value.protocol
      cidr_blocks     = ingress.value.cidr_blocks
      security_groups = ingress.value.security_groups
      description     = ingress.value.description
    }
  }

  # Egress is unrestricted by policy (the repo's 0.0.0.0/0 rule is about
  # inbound traffic). The default is Cloud Posse aws-ec2-instance's: all
  # outbound traffic. allowed_egress_rules replaces it.
  dynamic "egress" {
    for_each = var.allowed_egress_rules != null ? var.allowed_egress_rules : [{
      from_port       = 0
      to_port         = 0
      protocol        = "-1"
      cidr_blocks     = ["0.0.0.0/0"]
      security_groups = null
      description     = "Allow all outbound traffic"
    }]
    content {
      from_port       = egress.value.from_port
      to_port         = egress.value.to_port
      protocol        = egress.value.protocol
      cidr_blocks     = egress.value.cidr_blocks
      security_groups = egress.value.security_groups
      description     = egress.value.description
    }
  }

  tags = merge(var.tags, { Name = "${local.name_prefix}-sg" })
}

resource "aws_iam_role" "default" {
  count = local.enabled ? 1 : 0

  name = "${local.name_prefix}-role"

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

  tags = merge(var.tags, { Name = "${local.name_prefix}-role" })
}

resource "aws_iam_instance_profile" "default" {
  count = local.enabled ? 1 : 0

  name = "${local.name_prefix}-profile"
  role = aws_iam_role.default[0].name

  tags = merge(var.tags, { Name = "${local.name_prefix}-profile" })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  count = local.enabled && var.enable_ssm ? 1 : 0

  role       = aws_iam_role.default[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "custom" {
  count = local.enabled && var.custom_iam_policy != "" ? 1 : 0

  name   = "${local.name_prefix}-custom-policy"
  role   = aws_iam_role.default[0].id
  policy = var.custom_iam_policy
}

# Latest Amazon Linux 2023 when no ami is given (Amazon Linux 2 reached end of
# life on 2026-06-30). Read only when used, as Cloud Posse does.
data "aws_ami" "default" {
  count = local.enabled && var.ami == "" ? 1 : 0

  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# Fails the plan when ssh_key_pair names a key that does not exist, rather
# than the launch.
data "aws_key_pair" "existing" {
  count = local.enabled && local.ssh_key_pair != null ? 1 : 0

  key_name = local.ssh_key_pair
}
