# EC2 Launch Templates for Advanced Instance Configuration
# Provides IMDSv2 enforcement, user data templates, and consistent configuration

# Launch template for each instance configuration
resource "aws_launch_template" "instance" {
  for_each = var.enable_launch_templates ? local.instances : {}

  name_prefix   = "${var.tags["Environment"]}-${each.key}-lt-"
  description   = "Launch template for ${each.key} instance"
  image_id      = each.value.ami
  instance_type = each.value.instance_type
  key_name      = try(each.value.key_name, var.default_key_name, null)

  # IMDSv2 enforcement for security
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = var.enforce_imdsv2 ? "required" : "optional"
    http_put_response_hop_limit = var.imds_hop_limit
    instance_metadata_tags      = var.enable_instance_metadata_tags ? "enabled" : "disabled"
  }

  # Network interfaces configuration
  dynamic "network_interfaces" {
    for_each = var.enable_network_interface_config ? [1] : []
    content {
      associate_public_ip_address = try(each.value.associate_public_ip_address, false)
      delete_on_termination       = true
      security_groups            = try(each.value.security_groups, [])
      subnet_id                   = try(each.value.subnet_id, null)

      # Enhanced networking
      device_index = 0
    }
  }

  # EBS optimization
  ebs_optimized = try(each.value.ebs_optimized, var.default_ebs_optimized, true)

  # Block device mappings
  dynamic "block_device_mappings" {
    for_each = try(each.value.block_devices, var.default_block_devices, [])
    content {
      device_name = block_device_mappings.value.device_name

      ebs {
        volume_size           = try(block_device_mappings.value.volume_size, 20)
        volume_type           = try(block_device_mappings.value.volume_type, "gp3")
        iops                  = try(block_device_mappings.value.iops, null)
        throughput            = try(block_device_mappings.value.throughput, null)
        encrypted             = try(block_device_mappings.value.encrypted, true)
        kms_key_id            = try(block_device_mappings.value.kms_key_id, var.default_kms_key_id, null)
        delete_on_termination = try(block_device_mappings.value.delete_on_termination, true)
        snapshot_id           = try(block_device_mappings.value.snapshot_id, null)
      }
    }
  }

  # IAM instance profile
  iam_instance_profile {
    name = try(each.value.iam_instance_profile, var.default_iam_instance_profile, null) != null ? try(each.value.iam_instance_profile, var.default_iam_instance_profile) : null
  }

  # User data from template
  user_data = try(each.value.user_data_template, null) != null ? base64encode(templatefile(
    each.value.user_data_template,
    merge(
      try(each.value.user_data_vars, {}),
      {
        hostname    = each.key
        environment = var.tags["Environment"]
      }
    )
  )) : (try(each.value.user_data, null) != null ? base64encode(each.value.user_data) : null)

  # Monitoring
  monitoring {
    enabled = try(each.value.detailed_monitoring, var.enable_detailed_monitoring, true)
  }

  # Placement
  dynamic "placement" {
    for_each = try(each.value.placement_group, null) != null ? [1] : []
    content {
      group_name = each.value.placement_group
    }
  }

  # Credit specification for T instances
  dynamic "credit_specification" {
    for_each = can(regex("^t[2-4]", each.value.instance_type)) ? [1] : []
    content {
      cpu_credits = try(each.value.cpu_credits, "standard")
    }
  }

  # Capacity reservation
  dynamic "capacity_reservation_specification" {
    for_each = try(each.value.capacity_reservation_id, null) != null ? [1] : []
    content {
      capacity_reservation_target {
        capacity_reservation_id = each.value.capacity_reservation_id
      }
    }
  }

  # License specification
  dynamic "license_specification" {
    for_each = try(each.value.license_configuration_arn, null) != null ? [1] : []
    content {
      license_configuration_arn = each.value.license_configuration_arn
    }
  }

  # Enclave options
  dynamic "enclave_options" {
    for_each = try(each.value.enable_nitro_enclave, false) ? [1] : []
    content {
      enabled = true
    }
  }

  # Hibernation
  dynamic "hibernation_options" {
    for_each = try(each.value.enable_hibernation, false) ? [1] : []
    content {
      configured = true
    }
  }

  # Maintenance options
  dynamic "maintenance_options" {
    for_each = try(each.value.auto_recovery, null) != null ? [1] : []
    content {
      auto_recovery = each.value.auto_recovery
    }
  }

  # Private DNS name options
  dynamic "private_dns_name_options" {
    for_each = var.enable_resource_name_dns ? [1] : []
    content {
      enable_resource_name_dns_aaaa_record = try(each.value.enable_ipv6, false)
      enable_resource_name_dns_a_record    = true
      hostname_type                        = try(each.value.hostname_type, "ip-name")
    }
  }

  # Instance requirements (for Spot/Auto Scaling)
  dynamic "instance_requirements" {
    for_each = try(each.value.instance_requirements, null) != null ? [1] : []
    content {
      memory_mib {
        min = try(each.value.instance_requirements.memory_mib_min, 1024)
        max = try(each.value.instance_requirements.memory_mib_max, null)
      }

      vcpu_count {
        min = try(each.value.instance_requirements.vcpu_count_min, 1)
        max = try(each.value.instance_requirements.vcpu_count_max, null)
      }

      cpu_manufacturers             = try(each.value.instance_requirements.cpu_manufacturers, null)
      instance_generations          = try(each.value.instance_requirements.instance_generations, ["current"])
      accelerator_types             = try(each.value.instance_requirements.accelerator_types, null)
      burstable_performance         = try(each.value.instance_requirements.burstable_performance, null)
      require_hibernate_support     = try(each.value.instance_requirements.require_hibernate_support, null)
      spot_max_price_percentage_over_lowest_price = try(each.value.instance_requirements.spot_max_price_percentage, null)
    }
  }

  # Disable API termination
  disable_api_termination = try(each.value.disable_api_termination, var.default_disable_api_termination, false)

  # Instance initiated shutdown behavior
  instance_initiated_shutdown_behavior = try(each.value.shutdown_behavior, "stop")

  # Kernel and RAM disk IDs
  kernel_id  = try(each.value.kernel_id, null)
  ram_disk_id = try(each.value.ram_disk_id, null)

  # Tag specifications
  tag_specifications {
    resource_type = "instance"
    tags = merge(
      var.tags,
      try(each.value.tags, {}),
      {
        Name        = "${var.tags["Environment"]}-${each.key}"
        LaunchTemplate = true
      }
    )
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(
      var.tags,
      try(each.value.tags, {}),
      {
        Name        = "${var.tags["Environment"]}-${each.key}-volume"
        LaunchTemplate = true
      }
    )
  }

  tag_specifications {
    resource_type = "network-interface"
    tags = merge(
      var.tags,
      try(each.value.tags, {}),
      {
        Name        = "${var.tags["Environment"]}-${each.key}-eni"
        LaunchTemplate = true
      }
    )
  }

  tags = merge(
    var.tags,
    try(each.value.tags, {}),
    {
      Name = "${var.tags["Environment"]}-${each.key}-lt"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# Create EC2 instances from launch templates (if enabled)
resource "aws_instance" "from_launch_template" {
  for_each = var.enable_launch_templates && var.create_instances_from_templates ? local.instances : {}

  launch_template {
    id      = aws_launch_template.instance[each.key].id
    version = try(each.value.launch_template_version, "$Latest")
  }

  # Override subnet if needed (not specified in launch template network interface)
  subnet_id = !var.enable_network_interface_config ? try(each.value.subnet_id, null) : null

  # Override security groups if needed
  vpc_security_group_ids = !var.enable_network_interface_config ? try(each.value.security_groups, []) : null

  # Availability zone
  availability_zone = try(each.value.availability_zone, null)

  # Tenancy
  tenancy = try(each.value.tenancy, "default")

  # Host ID for dedicated hosts
  host_id = try(each.value.host_id, null)

  # Source/destination check
  source_dest_check = try(each.value.source_dest_check, true)

  # User data replacement behavior
  user_data_replace_on_change = try(each.value.user_data_replace_on_change, false)

  # Enable stop protection
  disable_api_stop = try(each.value.disable_api_stop, false)

  # Volume tags
  volume_tags = merge(
    var.tags,
    try(each.value.tags, {}),
    {
      Name = "${var.tags["Environment"]}-${each.key}-volume"
    }
  )

  # Root block device override (if not using launch template block devices)
  dynamic "root_block_device" {
    for_each = !try(each.value.use_launch_template_block_devices, true) ? [1] : []
    content {
      volume_size           = try(each.value.root_volume_size, 20)
      volume_type           = try(each.value.root_volume_type, "gp3")
      iops                  = try(each.value.root_volume_iops, null)
      throughput            = try(each.value.root_volume_throughput, null)
      encrypted             = try(each.value.root_volume_encrypted, true)
      kms_key_id            = try(each.value.root_volume_kms_key_id, var.default_kms_key_id, null)
      delete_on_termination = try(each.value.root_volume_delete_on_termination, true)
      tags = merge(
        var.tags,
        try(each.value.tags, {}),
        {
          Name = "${var.tags["Environment"]}-${each.key}-root"
        }
      )
    }
  }

  tags = merge(
    var.tags,
    try(each.value.tags, {}),
    {
      Name              = "${var.tags["Environment"]}-${each.key}"
      LaunchTemplate    = "true"
      LaunchTemplateId  = aws_launch_template.instance[each.key].id
    }
  )

  lifecycle {
    ignore_changes = [
      ami,
      user_data
    ]
  }

  depends_on = [
    aws_launch_template.instance
  ]
}

# CloudWatch dashboard for launch template metrics
resource "aws_cloudwatch_dashboard" "launch_templates" {
  count = var.enable_launch_templates && var.create_launch_template_dashboard ? 1 : 0

  dashboard_name = "${var.tags["Environment"]}-ec2-launch-templates"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          metrics = [
            for k, v in aws_launch_template.instance : [
              "AWS/EC2",
              "CPUUtilization",
              { stat = "Average", label = k }
            ]
          ]
          period = 300
          stat   = "Average"
          region = var.region
          title  = "CPU Utilization by Launch Template"
        }
      }
    ]
  })
}
