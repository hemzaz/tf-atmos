# Optional launch template (enable_launch_templates, default false: Cloud
# Posse's ec2-instance has none). With create_instances_from_templates the
# instance is launched from it (aws_instance.from_launch_template) instead of
# standalone (aws_instance.default); never both.

resource "aws_launch_template" "default" {
  #checkov:skip=CKV_AWS_88:Public IP is off unless a stack sets associate_public_ip_address = true
  #checkov:skip=CKV_AWS_79:http_tokens is "required" unless a stack sets metadata_http_tokens_required = false
  count = local.enabled && var.enable_launch_templates ? 1 : 0

  name_prefix   = "${local.name_prefix}-lt-"
  description   = "Launch template for the ${local.name_prefix} instance"
  image_id      = local.ami
  instance_type = var.instance_type
  key_name      = local.key_name

  metadata_options {
    http_endpoint               = local.metadata_options.http_endpoint
    http_tokens                 = local.metadata_options.http_tokens
    http_put_response_hop_limit = local.metadata_options.http_put_response_hop_limit
    instance_metadata_tags      = local.metadata_options.instance_metadata_tags
  }

  dynamic "network_interfaces" {
    for_each = var.enable_network_interface_config ? [1] : []
    content {
      associate_public_ip_address = var.associate_public_ip_address
      delete_on_termination       = true
      security_groups             = local.security_group_ids
      subnet_id                   = local.subnet
      device_index                = 0
    }
  }

  ebs_optimized = var.ebs_optimized

  dynamic "block_device_mappings" {
    for_each = var.ebs_block_devices
    content {
      device_name = block_device_mappings.value.device_name
      ebs {
        volume_size           = block_device_mappings.value.volume_size
        volume_type           = block_device_mappings.value.volume_type
        iops                  = block_device_mappings.value.iops
        throughput            = block_device_mappings.value.throughput
        encrypted             = block_device_mappings.value.encrypted
        kms_key_id            = try(coalesce(block_device_mappings.value.kms_key_id, var.root_block_device_kms_key_id), null)
        delete_on_termination = block_device_mappings.value.delete_on_termination
        snapshot_id           = block_device_mappings.value.snapshot_id
      }
    }
  }

  # Was `name = null`: an instance launched from the template had no role.
  iam_instance_profile {
    name = aws_iam_instance_profile.default[0].name
  }

  user_data = var.user_data != null ? base64encode(var.user_data) : null

  monitoring {
    enabled = var.monitoring
  }

  dynamic "credit_specification" {
    for_each = can(regex("^t[2-4]", var.instance_type)) ? [1] : []
    content {
      cpu_credits = "standard"
    }
  }

  dynamic "private_dns_name_options" {
    for_each = var.enable_resource_name_dns ? [1] : []
    content {
      enable_resource_name_dns_aaaa_record = false
      enable_resource_name_dns_a_record    = true
      hostname_type                        = "ip-name"
    }
  }

  disable_api_termination              = var.disable_api_termination
  instance_initiated_shutdown_behavior = "stop"

  dynamic "tag_specifications" {
    for_each = { instance = "", volume = "-volume", "network-interface" = "-eni" }
    content {
      resource_type = tag_specifications.key
      tags          = merge(var.tags, { Name = "${local.name_prefix}${tag_specifications.value}", LaunchTemplate = "true" })
    }
  }

  tags = merge(var.tags, { Name = "${local.name_prefix}-lt" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_instance" "from_launch_template" {
  #checkov:skip=CKV_AWS_79:http_tokens comes from the launch template, which requires IMDSv2 unless a stack sets metadata_http_tokens_required = false
  #checkov:skip=CKV_AWS_126:detailed monitoring is set by the launch template (monitoring, default true)
  #checkov:skip=CKV_AWS_135:ebs_optimized is set by the launch template
  count = local.enabled && local.from_template ? 1 : 0

  launch_template {
    id      = aws_launch_template.default[0].id
    version = "$Latest"
  }

  # Without a network interface in the template, the instance places itself.
  subnet_id              = !var.enable_network_interface_config ? local.subnet : null
  vpc_security_group_ids = !var.enable_network_interface_config ? local.security_group_ids : null

  # The root volume is the AMI's unless set here; set it as the standalone
  # instance does, so both paths encrypt it.
  root_block_device {
    volume_type           = var.root_volume_type
    volume_size           = var.root_volume_size
    delete_on_termination = var.delete_on_termination
    encrypted             = var.root_block_device_encrypted
    kms_key_id            = var.root_block_device_kms_key_id
  }

  tags = merge(var.tags, {
    Name             = local.name_prefix
    LaunchTemplate   = "true"
    LaunchTemplateId = aws_launch_template.default[0].id
  })

  lifecycle {
    ignore_changes = [ami, user_data]

    precondition {
      condition     = local.ssh_key_pair == null || one(data.aws_key_pair.existing[*].key_name) == local.ssh_key_pair
      error_message = "Instance ${local.name_prefix} references a key pair (ssh_key_pair) that does not exist in AWS."
    }
  }
}
