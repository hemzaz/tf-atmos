# ASG Launch Template Module - Main Configuration
# Version: 1.0.0

locals {
  name = "${var.name_prefix}-asg"

  common_tags = merge(
    var.tags,
    {
      Name        = local.name
      Environment = var.environment
      ManagedBy   = "terraform"
      Module      = "asg-launch-template"
    }
  )

  cloudwatch_agent_config = jsonencode({
    metrics = {
      namespace = "CustomMetrics/${local.name}"
      append_dimensions = {
        AutoScalingGroupName = "$${aws:AutoScalingGroupName}"
      }
      aggregation_dimensions = [["AutoScalingGroupName"]]
      metrics_collected = {
        mem = {
          measurement                 = [{ name = "mem_used_percent" }]
          metrics_collection_interval = 60
        }
        disk = {
          measurement                 = [{ name = "used_percent" }]
          metrics_collection_interval = 60
          resources                   = ["*"]
        }
      }
    }
  })

  # Default user data: install and start the CloudWatch agent (Amazon Linux 2023).
  cloudwatch_agent_user_data = <<-EOT
    #!/bin/bash
    set -euo pipefail
    dnf install -y amazon-cloudwatch-agent
    mkdir -p /opt/aws/amazon-cloudwatch-agent/etc
    cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'CWCONFIG'
    ${local.cloudwatch_agent_config}
    CWCONFIG
    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s \
      -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
  EOT

  # var.user_data is already base64 encoded.
  user_data_base64 = var.user_data != "" ? var.user_data : (var.enable_cloudwatch_agent ? base64encode(local.cloudwatch_agent_user_data) : null)

  alb_target_tracking_enabled = var.enable_alb_target_tracking && var.alb_target_group_arn != null
}

# ==============================================================================
# DATA SOURCES
# ==============================================================================

data "aws_partition" "current" {}

# Amazon Linux 2 reached end of support on 2026-06-30; default to Amazon Linux 2023.
data "aws_ami" "amazon_linux" {
  count = var.ami_id == null ? 1 : 0

  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

# ==============================================================================
# IAM ROLE FOR INSTANCES
# ==============================================================================

data "aws_iam_policy_document" "instance_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "instance" {
  count = var.iam_instance_profile == null ? 1 : 0

  name = "${local.name}-instance-role"

  assume_role_policy = data.aws_iam_policy_document.instance_assume_role.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  count = var.iam_instance_profile == null ? 1 : 0

  role       = aws_iam_role.instance[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch" {
  count = var.iam_instance_profile == null && var.enable_cloudwatch_agent ? 1 : 0

  role       = aws_iam_role.instance[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "instance" {
  count = var.iam_instance_profile == null ? 1 : 0

  name = "${local.name}-instance-profile"
  role = aws_iam_role.instance[0].name

  tags = local.common_tags
}

# ==============================================================================
# SECURITY GROUP
# ==============================================================================

resource "aws_security_group" "instance" {
  count = length(var.security_group_ids) == 0 ? 1 : 0

  name        = "${local.name}-sg"
  description = "Security group for ASG instances"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name}-sg"
    }
  )
}

# ==============================================================================
# LAUNCH TEMPLATE
# ==============================================================================

resource "aws_launch_template" "main" {
  name        = "${local.name}-lt"
  description = "Launch template for ${local.name}"

  image_id      = var.ami_id != null ? var.ami_id : data.aws_ami.amazon_linux[0].id
  instance_type = var.instance_type
  key_name      = var.key_name

  iam_instance_profile {
    name = var.iam_instance_profile != null ? var.iam_instance_profile : aws_iam_instance_profile.instance[0].name
  }

  vpc_security_group_ids = length(var.security_group_ids) > 0 ? var.security_group_ids : [aws_security_group.instance[0].id]

  user_data = local.user_data_base64

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = var.enable_imdsv2 ? "required" : "optional"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  monitoring {
    enabled = var.enable_monitoring
  }

  dynamic "block_device_mappings" {
    for_each = var.block_device_mappings
    content {
      device_name = block_device_mappings.value.device_name

      ebs {
        volume_size           = block_device_mappings.value.ebs.volume_size
        volume_type           = block_device_mappings.value.ebs.volume_type
        iops                  = block_device_mappings.value.ebs.iops
        throughput            = block_device_mappings.value.ebs.throughput
        encrypted             = block_device_mappings.value.ebs.encrypted
        delete_on_termination = block_device_mappings.value.ebs.delete_on_termination
      }
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(
      local.common_tags,
      {
        Name = "${local.name}-instance"
      }
    )
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(
      local.common_tags,
      {
        Name = "${local.name}-volume"
      }
    )
  }

  tags = local.common_tags
}

# ==============================================================================
# AUTO SCALING GROUP
# ==============================================================================

resource "aws_autoscaling_group" "main" {
  name                      = local.name
  vpc_zone_identifier       = var.subnet_ids
  min_size                  = var.min_size
  max_size                  = var.max_size
  desired_capacity          = var.desired_capacity
  health_check_type         = var.health_check_type
  health_check_grace_period = var.health_check_grace_period
  default_cooldown          = var.default_cooldown
  termination_policies      = var.termination_policies
  enabled_metrics           = var.enabled_metrics
  protect_from_scale_in     = var.protect_from_scale_in

  dynamic "launch_template" {
    for_each = var.enable_mixed_instances ? [] : [1]
    content {
      id      = aws_launch_template.main.id
      version = "$Latest"
    }
  }

  dynamic "mixed_instances_policy" {
    for_each = var.enable_mixed_instances ? [1] : []
    content {
      launch_template {
        launch_template_specification {
          launch_template_id = aws_launch_template.main.id
          version            = "$Latest"
        }

        dynamic "override" {
          for_each = var.instance_types
          content {
            instance_type = override.value
          }
        }
      }

      instances_distribution {
        on_demand_base_capacity                  = var.on_demand_base_capacity
        on_demand_percentage_above_base_capacity = var.on_demand_percentage_above_base
        spot_allocation_strategy                 = var.spot_allocation_strategy
        spot_max_price                           = var.spot_max_price
      }
    }
  }

  target_group_arns = var.alb_target_group_arn != null ? [var.alb_target_group_arn] : []

  dynamic "instance_refresh" {
    for_each = var.enable_instance_refresh ? [1] : []
    content {
      strategy = "Rolling"
      preferences {
        min_healthy_percentage = var.instance_refresh_min_healthy_percentage
        instance_warmup        = var.health_check_grace_period
      }
    }
  }

  dynamic "warm_pool" {
    for_each = var.enable_warm_pool ? [1] : []
    content {
      pool_state                  = "Stopped"
      min_size                    = var.warm_pool_min_size
      max_group_prepared_capacity = var.warm_pool_max_group_prepared_capacity
    }
  }

  dynamic "tag" {
    for_each = local.common_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [desired_capacity]
  }
}

# ==============================================================================
# AUTO SCALING POLICIES - TARGET TRACKING
# ==============================================================================

resource "aws_autoscaling_policy" "cpu" {
  count = var.enable_target_tracking_cpu ? 1 : 0

  name                   = "${local.name}-cpu-tracking"
  autoscaling_group_name = aws_autoscaling_group.main.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = var.cpu_target_value
  }
}

resource "aws_autoscaling_policy" "memory" {
  count = var.enable_target_tracking_memory ? 1 : 0

  name                   = "${local.name}-memory-tracking"
  autoscaling_group_name = aws_autoscaling_group.main.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    customized_metric_specification {
      metric_dimension {
        name  = "AutoScalingGroupName"
        value = aws_autoscaling_group.main.name
      }
      metric_name = "mem_used_percent"
      namespace   = "CustomMetrics/${local.name}"
      statistic   = "Average"
    }
    target_value = var.memory_target_value
  }
}

# ALBRequestCountPerTarget needs "<lb arn suffix>/<target group arn suffix>";
# the load balancer part cannot be derived from the target group ARN alone.
data "aws_lb_target_group" "alb" {
  count = local.alb_target_tracking_enabled ? 1 : 0

  arn = var.alb_target_group_arn
}

data "aws_lb" "alb" {
  count = local.alb_target_tracking_enabled ? 1 : 0

  arn = one(data.aws_lb_target_group.alb[0].load_balancer_arns)
}

resource "aws_autoscaling_policy" "alb" {
  count = local.alb_target_tracking_enabled ? 1 : 0

  name                   = "${local.name}-alb-tracking"
  autoscaling_group_name = aws_autoscaling_group.main.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${data.aws_lb.alb[0].arn_suffix}/${data.aws_lb_target_group.alb[0].arn_suffix}"
    }
    target_value = var.alb_target_value
  }
}

# ==============================================================================
# SCHEDULED SCALING
# ==============================================================================

resource "aws_autoscaling_schedule" "scheduled" {
  for_each = var.enable_scheduled_scaling ? { for action in var.scheduled_actions : action.name => action } : {}

  scheduled_action_name  = each.value.name
  autoscaling_group_name = aws_autoscaling_group.main.name
  min_size               = each.value.min_size
  max_size               = each.value.max_size
  desired_capacity       = each.value.desired_capacity
  recurrence             = each.value.recurrence
}

# ==============================================================================
# CLOUDWATCH ALARMS
# ==============================================================================

resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "${local.name}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 90
  alarm_description   = "This metric monitors high CPU utilization"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.main.name
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  count = var.alb_target_group_arn != null ? 1 : 0

  alarm_name          = "${local.name}-unhealthy-hosts"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 0
  alarm_description   = "This metric monitors unhealthy hosts"

  dimensions = {
    TargetGroup = split(":", var.alb_target_group_arn)[5]
  }

  tags = local.common_tags
}
