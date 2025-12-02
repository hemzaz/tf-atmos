################################################################################
# Data Sources
################################################################################

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

################################################################################
# Locals
################################################################################

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
  partition  = data.aws_partition.current.partition

  name_prefix = var.name

  default_tags = merge(
    var.tags,
    {
      ManagedBy = "Terraform"
      Module    = "cicd/codedeploy-app"
    }
  )

  # Determine deployment config name
  deployment_config_name = var.create_deployment_config ? aws_codedeploy_deployment_config.this[0].id : (
    var.deployment_config_name != null ? var.deployment_config_name : (
      var.compute_platform == "Server" ? "CodeDeployDefault.OneAtATime" : (
        var.compute_platform == "Lambda" ? "CodeDeployDefault.LambdaCanary10Percent5Minutes" : (
          var.compute_platform == "ECS" ? "CodeDeployDefault.ECSCanary10Percent5Minutes" : null
        )
      )
    )
  )
}

################################################################################
# IAM Role for CodeDeploy
################################################################################

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["codedeploy.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "this" {
  count = var.create_service_role ? 1 : 0

  name                 = "${local.name_prefix}-codedeploy-role"
  assume_role_policy   = data.aws_iam_policy_document.assume_role.json
  permissions_boundary = var.role_permissions_boundary

  tags = local.default_tags
}

# Attach AWS managed policy for CodeDeploy
resource "aws_iam_role_policy_attachment" "codedeploy" {
  count = var.create_service_role ? 1 : 0

  role = aws_iam_role.this[0].name
  policy_arn = var.compute_platform == "ECS" ? "arn:${local.partition}:iam::aws:policy/AWSCodeDeployRoleForECS" : (
    var.compute_platform == "Lambda" ? "arn:${local.partition}:iam::aws:policy/service-role/AWSCodeDeployRoleForLambda" : (
      "arn:${local.partition}:iam::aws:policy/service-role/AWSCodeDeployRole"
    )
  )
}

# Additional policy for Auto Scaling integration
data "aws_iam_policy_document" "autoscaling" {
  count = var.create_service_role && length(var.autoscaling_groups) > 0 ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "autoscaling:CompleteLifecycleAction",
      "autoscaling:DeleteLifecycleHook",
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeLifecycleHooks",
      "autoscaling:PutLifecycleHook",
      "autoscaling:RecordLifecycleActionHeartbeat",
      "autoscaling:CreateAutoScalingGroup",
      "autoscaling:UpdateAutoScalingGroup",
      "autoscaling:EnableMetricsCollection",
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribePolicies",
      "autoscaling:DescribeScheduledActions",
      "autoscaling:DescribeNotificationConfigurations",
      "autoscaling:DescribeLifecycleHooks",
      "autoscaling:SuspendProcesses",
      "autoscaling:ResumeProcesses",
      "autoscaling:AttachLoadBalancers",
      "autoscaling:AttachLoadBalancerTargetGroups",
      "autoscaling:PutScalingPolicy",
      "autoscaling:PutScheduledUpdateGroupAction",
      "autoscaling:PutNotificationConfiguration",
      "autoscaling:PutWarmPool",
      "autoscaling:DescribeScalingActivities",
      "autoscaling:DeleteAutoScalingGroup"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "autoscaling" {
  count = var.create_service_role && length(var.autoscaling_groups) > 0 ? 1 : 0

  name   = "${local.name_prefix}-autoscaling-policy"
  role   = aws_iam_role.this[0].id
  policy = data.aws_iam_policy_document.autoscaling[0].json
}

################################################################################
# CodeDeploy Application
################################################################################

resource "aws_codedeploy_app" "this" {
  name             = local.name_prefix
  compute_platform = var.compute_platform

  tags = local.default_tags
}

################################################################################
# Custom Deployment Configuration
################################################################################

resource "aws_codedeploy_deployment_config" "this" {
  count = var.create_deployment_config ? 1 : 0

  deployment_config_name = "${local.name_prefix}-config"
  compute_platform       = var.compute_platform

  # Traffic routing configuration for Lambda and ECS
  dynamic "traffic_routing_config" {
    for_each = var.compute_platform == "Lambda" || var.compute_platform == "ECS" ? [1] : []
    content {
      type = var.deployment_config_type

      dynamic "time_based_canary" {
        for_each = var.deployment_config_type == "TimeBasedCanary" ? [1] : []
        content {
          percentage = var.canary_percentage
          interval   = var.canary_interval
        }
      }

      dynamic "time_based_linear" {
        for_each = var.deployment_config_type == "TimeBasedLinear" ? [1] : []
        content {
          percentage = var.linear_percentage
          interval   = var.linear_interval
        }
      }
    }
  }

  # Minimum healthy hosts configuration for EC2/On-Premises
  dynamic "minimum_healthy_hosts" {
    for_each = var.compute_platform == "Server" ? [1] : []
    content {
      type  = "FLEET_PERCENT"
      value = 75
    }
  }
}

################################################################################
# CodeDeploy Deployment Group
################################################################################

resource "aws_codedeploy_deployment_group" "this" {
  app_name               = aws_codedeploy_app.this.name
  deployment_group_name  = "${local.name_prefix}-group"
  service_role_arn       = var.create_service_role ? aws_iam_role.this[0].arn : var.service_role_arn
  deployment_config_name = local.deployment_config_name

  autoscaling_groups           = var.autoscaling_groups
  outdated_instances_strategy  = var.outdated_instances_strategy
  termination_hook_enabled     = var.termination_hook_enabled

  tags = local.default_tags

  # EC2 tag filters
  dynamic "ec2_tag_filter" {
    for_each = var.ec2_tag_filters
    content {
      key   = ec2_tag_filter.value.key
      type  = coalesce(ec2_tag_filter.value.type, "KEY_AND_VALUE")
      value = ec2_tag_filter.value.value
    }
  }

  # EC2 tag sets (for AND/OR logic)
  dynamic "ec2_tag_set" {
    for_each = var.ec2_tag_set
    content {
      dynamic "ec2_tag_filter" {
        for_each = ec2_tag_set.value.ec2_tag_filter
        content {
          key   = ec2_tag_filter.value.key
          type  = coalesce(ec2_tag_filter.value.type, "KEY_AND_VALUE")
          value = ec2_tag_filter.value.value
        }
      }
    }
  }

  # On-premises tag filters
  dynamic "on_premises_instance_tag_filter" {
    for_each = var.on_premises_tag_filters
    content {
      key   = on_premises_instance_tag_filter.value.key
      type  = coalesce(on_premises_instance_tag_filter.value.type, "KEY_AND_VALUE")
      value = on_premises_instance_tag_filter.value.value
    }
  }

  # ECS service configuration
  dynamic "ecs_service" {
    for_each = var.compute_platform == "ECS" && var.ecs_cluster_name != null && var.ecs_service_name != null ? [1] : []
    content {
      cluster_name = var.ecs_cluster_name
      service_name = var.ecs_service_name
    }
  }

  # Deployment style
  deployment_style {
    deployment_option = var.deployment_option
    deployment_type   = var.deployment_type
  }

  # Blue/green deployment configuration
  dynamic "blue_green_deployment_config" {
    for_each = var.deployment_type == "BLUE_GREEN" && var.blue_green_deployment_config != null ? [1] : []
    content {
      dynamic "terminate_blue_instances_on_deployment_success" {
        for_each = var.blue_green_deployment_config.terminate_blue_instances_on_deployment_success != null ? [1] : []
        content {
          action                           = var.blue_green_deployment_config.terminate_blue_instances_on_deployment_success.action
          termination_wait_time_in_minutes = var.blue_green_deployment_config.terminate_blue_instances_on_deployment_success.termination_wait_time_in_minutes
        }
      }

      dynamic "deployment_ready_option" {
        for_each = var.blue_green_deployment_config.deployment_ready_option != null ? [1] : []
        content {
          action_on_timeout    = var.blue_green_deployment_config.deployment_ready_option.action_on_timeout
          wait_time_in_minutes = var.blue_green_deployment_config.deployment_ready_option.wait_time_in_minutes
        }
      }

      dynamic "green_fleet_provisioning_option" {
        for_each = var.blue_green_deployment_config.green_fleet_provisioning_option != null ? [1] : []
        content {
          action = var.blue_green_deployment_config.green_fleet_provisioning_option.action
        }
      }
    }
  }

  # Load balancer configuration
  dynamic "load_balancer_info" {
    for_each = var.load_balancer_info != null ? [1] : []
    content {
      dynamic "target_group_info" {
        for_each = var.load_balancer_info.target_group_arns != null ? [1] : []
        content {
          name = null # Must be null when using target_group_arns
        }
      }

      dynamic "target_group_pair_info" {
        for_each = var.load_balancer_info.target_group_pair != null ? [1] : []
        content {
          prod_traffic_route {
            listener_arns = var.load_balancer_info.target_group_pair.prod_traffic_route_listener_arns
          }

          dynamic "test_traffic_route" {
            for_each = var.load_balancer_info.target_group_pair.test_traffic_route_listener_arns != null ? [1] : []
            content {
              listener_arns = var.load_balancer_info.target_group_pair.test_traffic_route_listener_arns
            }
          }

          target_group {
            name = var.load_balancer_info.target_group_pair.target_group_name_blue
          }

          target_group {
            name = var.load_balancer_info.target_group_pair.target_group_name_green
          }
        }
      }

      dynamic "elb_info" {
        for_each = var.load_balancer_info.elb_info != null ? var.load_balancer_info.elb_info : []
        content {
          name = elb_info.value.name
        }
      }
    }
  }

  # Auto rollback configuration
  auto_rollback_configuration {
    enabled = var.enable_auto_rollback
    events  = var.enable_auto_rollback ? var.auto_rollback_events : []
  }

  # Alarm configuration
  dynamic "alarm_configuration" {
    for_each = var.alarm_configuration != null ? [1] : []
    content {
      enabled                   = var.alarm_configuration.enabled
      alarms                    = var.alarm_configuration.alarm_names
      ignore_poll_alarm_failure = coalesce(var.alarm_configuration.ignore_poll_alarm_failure, false)
    }
  }

  # Trigger configurations
  dynamic "trigger_configuration" {
    for_each = var.trigger_configurations
    content {
      trigger_name       = trigger_configuration.value.trigger_name
      trigger_events     = trigger_configuration.value.trigger_events
      trigger_target_arn = trigger_configuration.value.trigger_target_arn
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.codedeploy
  ]
}
