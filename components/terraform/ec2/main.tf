locals {
  # Filter enabled instances
  instances = {
    for k, v in var.instances : k => v if lookup(v, "enabled", true)
  }

  # Check if we need a global key
  create_global_key = var.create_ssh_keys && var.global_key_name != null

  # Normalize the key_name value to handle different ways of specifying null/empty values
  instances_with_normalized_key_names = {
    for k, v in local.instances : k => merge(v, {
      normalized_key_name = try(
        # Check if key_name is explicitly set to null
        v.key_name == null ? null :
        # Check if key_name is an empty string
        v.key_name == "" ? null :
        # Use the specified key_name value
        v.key_name,
        # Default to null if key_name is not specified at all
        null
      )
    })
  }

  # Define global key name with a consistent prefix pattern
  global_key_name = local.create_global_key ? "${var.tags["Environment"]}-global-${var.global_key_name}" : null

  # Determine which instances need individual SSH keys to be created
  instances_requiring_keys = {
    for k, v in local.instances_with_normalized_key_names : k => v
    if var.create_ssh_keys &&
    v.normalized_key_name == null &&
    var.default_key_name == null &&
    !local.create_global_key
  }

  # Determine instances that will use the global key
  instances_using_global_key = {
    for k, v in local.instances_with_normalized_key_names : k => v
    if var.create_ssh_keys &&
    v.normalized_key_name == null &&
    var.default_key_name == null &&
    local.create_global_key
  }
}

# Generate individual keys for instances
resource "tls_private_key" "ssh_key" {
  for_each  = local.instances_requiring_keys
  algorithm = var.ssh_key_algorithm
  rsa_bits  = var.ssh_key_algorithm == "RSA" ? var.ssh_key_rsa_bits : null

  lifecycle {
    # Prevent recreation of keys, which helps with idempotency
    # Terraform will error if this can't be achieved rather than replacing the key
    prevent_destroy = true

    # Add preconditions to validate that key parameters haven't changed
    precondition {
      condition     = var.ssh_key_algorithm == "RSA" || var.ssh_key_algorithm == "ED25519"
      error_message = "Only RSA and ED25519 algorithms are supported for SSH key generation."
    }

    # For RSA keys, validate the bit size
    precondition {
      condition     = var.ssh_key_algorithm != "RSA" || (var.ssh_key_rsa_bits >= 2048 && var.ssh_key_rsa_bits <= 8192)
      error_message = "For RSA keys, rsa_bits must be between 2048 and 8192."
    }
  }
}

# Generate global SSH key if specified
resource "tls_private_key" "global_ssh_key" {
  count     = local.create_global_key ? 1 : 0
  algorithm = var.ssh_key_algorithm
  rsa_bits  = var.ssh_key_algorithm == "RSA" ? var.ssh_key_rsa_bits : null

  lifecycle {
    # Prevent recreation of keys, which helps with idempotency
    # Terraform will error if this can't be achieved rather than replacing the key
    prevent_destroy = true

    # Add preconditions to validate that key parameters haven't changed
    precondition {
      condition     = var.ssh_key_algorithm == "RSA" || var.ssh_key_algorithm == "ED25519"
      error_message = "Only RSA and ED25519 algorithms are supported for SSH key generation."
    }

    # For RSA keys, validate the bit size
    precondition {
      condition     = var.ssh_key_algorithm != "RSA" || (var.ssh_key_rsa_bits >= 2048 && var.ssh_key_rsa_bits <= 8192)
      error_message = "For RSA keys, rsa_bits must be between 2048 and 8192."
    }
  }
}

# Create individual key pairs for instances
resource "aws_key_pair" "generated" {
  for_each   = local.instances_requiring_keys
  key_name   = "${var.tags["Environment"]}-${each.key}-ec2-ssh-key"
  public_key = tls_private_key.ssh_key[each.key].public_key_openssh

  tags = merge(
    var.tags,
    lookup(each.value, "tags", {}),
    {
      Name = "${var.tags["Environment"]}-${each.key}-ec2-ssh-key"
    }
  )
}

# Create global key pair if specified
resource "aws_key_pair" "global" {
  count      = local.create_global_key ? 1 : 0
  key_name   = local.global_key_name
  public_key = tls_private_key.global_ssh_key[0].public_key_openssh

  tags = merge(
    var.tags,
    {
      Name = local.global_key_name
      Type = "global"
    }
  )
}

# Store individual instance SSH keys in Secrets Manager
resource "aws_secretsmanager_secret" "ssh_key" {
  for_each = var.store_ssh_keys_in_secrets_manager ? local.instances_requiring_keys : {}

  name        = "ssh-key/${var.tags["Environment"]}/${each.key}"
  description = "SSH private key for ${each.key} EC2 instance"

  tags = merge(
    var.tags,
    lookup(each.value, "tags", {}),
    {
      Name         = "${var.tags["Environment"]}-${each.key}-ssh-key"
      InstanceName = "${var.tags["Environment"]}-${each.key}"
      KeyType      = "instance"
    }
  )
}

resource "aws_secretsmanager_secret_version" "ssh_key" {
  for_each  = var.store_ssh_keys_in_secrets_manager ? local.instances_requiring_keys : {}
  secret_id = aws_secretsmanager_secret.ssh_key[each.key].id

  # Include all metadata directly in the secret value, including instance_id
  # This eliminates the need for local-exec provisioner
  secret_string = jsonencode({
    private_key_pem     = tls_private_key.ssh_key[each.key].private_key_pem
    public_key_openssh  = tls_private_key.ssh_key[each.key].public_key_openssh
    key_name            = aws_key_pair.generated[each.key].key_name
    instance_name       = each.key
    instance_id         = aws_instance.instances[each.key].id
    instance_private_ip = aws_instance.instances[each.key].private_ip
    instance_public_ip  = aws_instance.instances[each.key].public_ip
    vpc_id              = var.vpc_id
    subnet_id           = aws_instance.instances[each.key].subnet_id
    security_group_id   = aws_security_group.instances[each.key].id
    environment         = var.tags["Environment"]
  })

  depends_on = [aws_instance.instances]

  lifecycle {
    # Add validation to ensure all required information is available
    precondition {
      condition     = aws_instance.instances[each.key].id != ""
      error_message = "Instance ID must be available before creating secret version."
    }
  }
}

# SSH private keys stay regular (non-ephemeral) values: aws_key_pair.public_key is not a
# write-only argument, so an ephemeral tls_private_key cannot feed it, and the key pair is
# already in state through tls_private_key. secret_string_wo would therefore hide nothing.

# Store global SSH key in Secrets Manager
resource "aws_secretsmanager_secret" "global_ssh_key" {
  count = var.store_ssh_keys_in_secrets_manager && local.create_global_key ? 1 : 0

  name        = "ssh-key/${var.tags["Environment"]}/global-keys/${var.global_key_name}"
  description = "Global SSH private key for ${var.tags["Environment"]} environment"

  tags = merge(
    var.tags,
    {
      Name    = "${var.tags["Environment"]}-global-ssh-key"
      KeyType = "global"
    }
  )
}

resource "aws_secretsmanager_secret_version" "global_ssh_key" {
  count     = var.store_ssh_keys_in_secrets_manager && local.create_global_key ? 1 : 0
  secret_id = aws_secretsmanager_secret.global_ssh_key[0].id
  secret_string = jsonencode({
    private_key_pem    = tls_private_key.global_ssh_key[0].private_key_pem
    public_key_openssh = tls_private_key.global_ssh_key[0].public_key_openssh
    key_name           = aws_key_pair.global[0].key_name
    environment        = var.tags["Environment"]
    used_by_instances  = keys(local.instances_using_global_key)
    # Instance IDs are included directly, replacing the local-exec secret update that
    # overwrote this version out of band
    instance_details = { for k, v in local.instances_using_global_key : k => aws_instance.instances[k].id }
  })
}

locals {
  # Determine the AMI to use, with proper fallback to data source
  default_ami = var.default_ami_id != "" ? var.default_ami_id : data.aws_ami.default.id

  # Same shape as default_ami: caller's value wins, otherwise resolve it.
  default_egress_prefix_list_ids = length(var.vpc_endpoint_prefix_list_ids) > 0 ? var.vpc_endpoint_prefix_list_ids : [data.aws_prefix_list.s3[0].id]
}

resource "aws_instance" "instances" {
  for_each = local.instances

  ami                    = coalesce(each.value.ami_id, local.default_ami)
  instance_type          = each.value.instance_type
  key_name               = contains(keys(local.instances_requiring_keys), each.key) ? aws_key_pair.generated[each.key].key_name : (contains(keys(local.instances_using_global_key), each.key) ? aws_key_pair.global[0].key_name : lookup(local.instances_with_normalized_key_names[each.key], "normalized_key_name", var.default_key_name))
  vpc_security_group_ids = concat([aws_security_group.instances[each.key].id], lookup(each.value, "additional_security_group_ids", []))
  subnet_id              = coalesce(each.value.subnet_id, var.subnet_ids[0])
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

  # SECURITY: Enforce IMDSv2 to prevent SSRF attacks
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # Enforce IMDSv2 (not optional)
    http_put_response_hop_limit = 1          # Limit to instance itself
    instance_metadata_tags      = "enabled"  # Allow instance tags in metadata
  }

  tags = merge(
    var.tags,
    lookup(each.value, "tags", {}),
    {
      Name = "${var.tags["Environment"]}-${each.key}"
    }
  )

  lifecycle {
    # AMI updates never replace instances in place
    ignore_changes = [ami]

    # Check that we have a valid key_name
    precondition {
      condition = (
        contains(keys(local.instances_requiring_keys), each.key) ||
        contains(keys(local.instances_using_global_key), each.key) ||
        lookup(local.instances_with_normalized_key_names[each.key], "normalized_key_name", null) != null ||
        var.default_key_name != null
      )
      error_message = "Instance ${each.key} does not have a valid key_name (either individual, global, or default)."
    }

    # Validate that existing keys referenced actually exist (validation happens via data source)
    precondition {
      condition     = lookup(local.instances_with_normalized_key_names[each.key], "normalized_key_name", null) == null || contains(keys(data.aws_key_pair.existing), each.key) || var.default_key_name == lookup(local.instances_with_normalized_key_names[each.key], "normalized_key_name", null)
      error_message = "Instance ${each.key} references key_name '${lookup(local.instances_with_normalized_key_names[each.key], "normalized_key_name", "")}' which does not exist in AWS. Verify the key exists or let the component create it."
    }
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

  dynamic "egress" {
    for_each = lookup(each.value, "allowed_egress_rules", [{
      from_port       = 443
      to_port         = 443
      protocol        = "tcp"
      prefix_list_ids = local.default_egress_prefix_list_ids
      description     = "Allow HTTPS outbound traffic to AWS services via VPC endpoints"
    }])

    content {
      from_port       = egress.value.from_port
      to_port         = egress.value.to_port
      protocol        = egress.value.protocol
      cidr_blocks     = lookup(egress.value, "cidr_blocks", null)
      prefix_list_ids = lookup(egress.value, "prefix_list_ids", null)
      security_groups = lookup(egress.value, "security_groups", null)
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

# The default egress rule restricts outbound HTTPS to AWS service prefix lists
# instead of 0.0.0.0/0. Callers may pass their own ids; when they do not, the
# region's S3 gateway prefix list is resolved here rather than demanded as an
# input. Requiring that input is what made this component unplannable in every
# stack, since no stack supplied it.
data "aws_prefix_list" "s3" {
  count = length(var.vpc_endpoint_prefix_list_ids) == 0 ? 1 : 0
  name  = "com.amazonaws.${var.region}.s3"
}

# Verify existing key pairs exist
data "aws_key_pair" "existing" {
  for_each = { for k, v in local.instances_with_normalized_key_names : k => v
    if v.normalized_key_name != null &&
    !contains(keys(local.instances_requiring_keys), k) &&
    !contains(keys(local.instances_using_global_key), k)
  }

  key_name = each.value.normalized_key_name

  # The data source will fail if the key doesn't exist
  # This provides validation at plan time
}

data "aws_ami" "default" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}
