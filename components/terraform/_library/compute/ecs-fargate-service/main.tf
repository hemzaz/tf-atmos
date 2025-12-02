# ECS Fargate Service Module - Main Configuration
# Version: 1.0.0

# ==============================================================================
# LOCAL VALUES
# ==============================================================================

locals {
  cluster_name = var.create_cluster ? "${var.name_prefix}-${var.service_name}-cluster" : var.cluster_name
  log_group_name = var.log_group_name != null ? var.log_group_name : "/ecs/${var.name_prefix}/${var.service_name}"

  common_tags = merge(
    var.tags,
    {
      Name        = "${var.name_prefix}-${var.service_name}"
      Environment = var.environment
      Service     = var.service_name
      ManagedBy   = "terraform"
      Module      = "ecs-fargate-service"
    }
  )

  # Capacity provider strategy
  capacity_provider_strategy = var.enable_fargate_spot ? [
    {
      capacity_provider = "FARGATE"
      weight            = var.fargate_base_weight
      base              = var.desired_count > 0 ? 1 : 0
    },
    {
      capacity_provider = "FARGATE_SPOT"
      weight            = var.fargate_spot_weight
      base              = 0
    }
  ] : [
    {
      capacity_provider = "FARGATE"
      weight            = 100
      base              = 0
    }
  ]
}

# ==============================================================================
# ECS CLUSTER
# ==============================================================================

resource "aws_ecs_cluster" "main" {
  count = var.create_cluster ? 1 : 0

  name = local.cluster_name

  setting {
    name  = "containerInsights"
    value = var.enable_container_insights ? "enabled" : "disabled"
  }

  configuration {
    execute_command_configuration {
      logging = "DEFAULT"
    }
  }

  tags = merge(
    local.common_tags,
    {
      Name = local.cluster_name
    }
  )
}

# Cluster capacity providers
resource "aws_ecs_cluster_capacity_providers" "main" {
  count = var.create_cluster ? 1 : 0

  cluster_name = aws_ecs_cluster.main[0].name

  capacity_providers = var.enable_fargate_spot ? ["FARGATE", "FARGATE_SPOT"] : ["FARGATE"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = var.fargate_base_weight
    base              = var.desired_count > 0 ? 1 : 0
  }

  dynamic "default_capacity_provider_strategy" {
    for_each = var.enable_fargate_spot ? [1] : []
    content {
      capacity_provider = "FARGATE_SPOT"
      weight            = var.fargate_spot_weight
      base              = 0
    }
  }
}

# ==============================================================================
# IAM ROLES
# ==============================================================================

# Task execution role (required for pulling images, writing logs)
resource "aws_iam_role" "execution" {
  count = var.execution_role_arn == null ? 1 : 0

  name = "${var.name_prefix}-${var.service_name}-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "execution" {
  count = var.execution_role_arn == null ? 1 : 0

  role       = aws_iam_role.execution[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Additional policy for Secrets Manager and SSM Parameter Store
resource "aws_iam_role_policy" "execution_secrets" {
  count = var.execution_role_arn == null && length(var.secrets) > 0 ? 1 : 0

  name = "${var.name_prefix}-${var.service_name}-execution-secrets"
  role = aws_iam_role.execution[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "ssm:GetParameters",
          "kms:Decrypt"
        ]
        Resource = values(var.secrets)
      }
    ]
  })
}

# Task role (for application permissions)
resource "aws_iam_role" "task" {
  count = var.task_role_arn == null ? 1 : 0

  name = "${var.name_prefix}-${var.service_name}-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

# Attach custom policies to task role
resource "aws_iam_role_policy_attachment" "task" {
  for_each = toset(var.task_role_arn == null ? var.task_role_policies : [])

  role       = aws_iam_role.task[0].name
  policy_arn = each.value
}

# Policy for ECS Exec
resource "aws_iam_role_policy" "task_exec" {
  count = var.task_role_arn == null && var.enable_execute_command ? 1 : 0

  name = "${var.name_prefix}-${var.service_name}-task-exec"
  role = aws_iam_role.task[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource = "*"
      }
    ]
  })
}

# Policy for X-Ray
resource "aws_iam_role_policy" "task_xray" {
  count = var.task_role_arn == null && var.enable_xray_tracing ? 1 : 0

  name = "${var.name_prefix}-${var.service_name}-task-xray"
  role = aws_iam_role.task[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ]
        Resource = "*"
      }
    ]
  })
}

# ==============================================================================
# SECURITY GROUP
# ==============================================================================

resource "aws_security_group" "service" {
  count = length(var.security_group_ids) == 0 ? 1 : 0

  name        = "${var.name_prefix}-${var.service_name}-sg"
  description = "Security group for ECS Fargate service ${var.service_name}"
  vpc_id      = var.vpc_id

  tags = merge(
    local.common_tags,
    {
      Name = "${var.name_prefix}-${var.service_name}-sg"
    }
  )
}

resource "aws_security_group_rule" "service_ingress" {
  count = length(var.security_group_ids) == 0 ? 1 : 0

  type              = "ingress"
  from_port         = var.container_port
  to_port           = var.container_port
  protocol          = "tcp"
  cidr_blocks       = var.allowed_cidr_blocks
  security_group_id = aws_security_group.service[0].id
  description       = "Allow inbound traffic on container port"
}

resource "aws_security_group_rule" "service_egress" {
  count = length(var.security_group_ids) == 0 ? 1 : 0

  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.service[0].id
  description       = "Allow all outbound traffic"
}

# ==============================================================================
# CLOUDWATCH LOG GROUP
# ==============================================================================

resource "aws_cloudwatch_log_group" "service" {
  count = var.enable_cloudwatch_logs ? 1 : 0

  name              = local.log_group_name
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

# ==============================================================================
# TASK DEFINITION
# ==============================================================================

resource "aws_ecs_task_definition" "main" {
  family                   = "${var.name_prefix}-${var.service_name}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = var.execution_role_arn != null ? var.execution_role_arn : aws_iam_role.execution[0].arn
  task_role_arn            = var.task_role_arn != null ? var.task_role_arn : aws_iam_role.task[0].arn

  container_definitions = jsonencode(var.container_definitions)

  runtime_platform {
    operating_system_family = var.runtime_platform.operating_system_family
    cpu_architecture        = var.runtime_platform.cpu_architecture
  }

  ephemeral_storage {
    size_in_gib = var.ephemeral_storage_size_gb
  }

  dynamic "volume" {
    for_each = var.enable_efs_volumes ? var.efs_volumes : []
    content {
      name = volume.value.name

      efs_volume_configuration {
        file_system_id          = volume.value.file_system_id
        root_directory          = volume.value.root_directory
        transit_encryption      = volume.value.transit_encryption
        transit_encryption_port = volume.value.transit_encryption == "ENABLED" ? 2999 : null

        dynamic "authorization_config" {
          for_each = volume.value.access_point_id != null ? [1] : []
          content {
            access_point_id = volume.value.access_point_id
          }
        }
      }
    }
  }

  tags = local.common_tags
}

# ==============================================================================
# SERVICE DISCOVERY
# ==============================================================================

resource "aws_service_discovery_service" "main" {
  count = var.enable_service_discovery ? 1 : 0

  name = var.service_name

  dns_config {
    namespace_id = var.service_discovery_namespace_id

    dns_records {
      ttl  = var.service_discovery_dns_ttl
      type = var.service_discovery_dns_type
    }

    routing_policy = var.service_discovery_routing_policy
  }

  health_check_custom_config {
    failure_threshold = 1
  }

  tags = local.common_tags
}

# ==============================================================================
# ECS SERVICE
# ==============================================================================

resource "aws_ecs_service" "main" {
  name            = var.service_name
  cluster         = var.create_cluster ? aws_ecs_cluster.main[0].id : var.cluster_name
  task_definition = aws_ecs_task_definition.main.arn
  desired_count   = var.desired_count
  launch_type     = var.enable_fargate_spot ? null : "FARGATE"

  enable_execute_command = var.enable_execute_command
  force_new_deployment   = var.force_new_deployment

  network_configuration {
    subnets          = var.subnet_ids
    assign_public_ip = var.assign_public_ip
    security_groups  = length(var.security_group_ids) > 0 ? var.security_group_ids : [aws_security_group.service[0].id]
  }

  deployment_configuration {
    maximum_percent         = var.deployment_maximum_percent
    minimum_healthy_percent = var.deployment_minimum_healthy_percent

    deployment_circuit_breaker {
      enable   = var.enable_deployment_circuit_breaker
      rollback = var.enable_deployment_circuit_breaker
    }
  }

  # Capacity provider strategy (for Fargate Spot)
  dynamic "capacity_provider_strategy" {
    for_each = var.enable_fargate_spot ? local.capacity_provider_strategy : []
    content {
      capacity_provider = capacity_provider_strategy.value.capacity_provider
      weight            = capacity_provider_strategy.value.weight
      base              = capacity_provider_strategy.value.base
    }
  }

  # Load balancer configuration
  dynamic "load_balancer" {
    for_each = var.enable_load_balancer && var.target_group_arn != null ? [1] : []
    content {
      target_group_arn = var.target_group_arn
      container_name   = var.container_name
      container_port   = var.container_port
    }
  }

  health_check_grace_period_seconds = var.enable_load_balancer && var.target_group_arn != null ? var.health_check_grace_period_seconds : null

  # Service discovery
  dynamic "service_registries" {
    for_each = var.enable_service_discovery ? [1] : []
    content {
      registry_arn = aws_service_discovery_service.main[0].arn
    }
  }

  # Blue/green deployment via CodeDeploy
  deployment_controller {
    type = var.enable_blue_green_deployment ? "CODE_DEPLOY" : "ECS"
  }

  tags = local.common_tags

  # Ignore changes to desired_count if autoscaling is enabled
  lifecycle {
    ignore_changes = var.enable_autoscaling ? [desired_count] : []
  }

  depends_on = [
    aws_iam_role_policy_attachment.execution
  ]
}

# ==============================================================================
# AUTO-SCALING
# ==============================================================================

resource "aws_appautoscaling_target" "service" {
  count = var.enable_autoscaling ? 1 : 0

  max_capacity       = var.autoscaling_max_capacity
  min_capacity       = var.autoscaling_min_capacity
  resource_id        = "service/${var.create_cluster ? aws_ecs_cluster.main[0].name : var.cluster_name}/${aws_ecs_service.main.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# CPU-based auto-scaling
resource "aws_appautoscaling_policy" "cpu" {
  count = var.enable_autoscaling ? 1 : 0

  name               = "${var.name_prefix}-${var.service_name}-cpu-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.service[0].resource_id
  scalable_dimension = aws_appautoscaling_target.service[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.service[0].service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = var.cpu_target_value
    scale_in_cooldown  = var.scale_in_cooldown
    scale_out_cooldown = var.scale_out_cooldown

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}

# Memory-based auto-scaling
resource "aws_appautoscaling_policy" "memory" {
  count = var.enable_autoscaling ? 1 : 0

  name               = "${var.name_prefix}-${var.service_name}-memory-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.service[0].resource_id
  scalable_dimension = aws_appautoscaling_target.service[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.service[0].service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = var.memory_target_value
    scale_in_cooldown  = var.scale_in_cooldown
    scale_out_cooldown = var.scale_out_cooldown

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
  }
}

# ALB request count-based auto-scaling
resource "aws_appautoscaling_policy" "alb" {
  count = var.enable_autoscaling && var.enable_alb_target_tracking && var.target_group_arn != null ? 1 : 0

  name               = "${var.name_prefix}-${var.service_name}-alb-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.service[0].resource_id
  scalable_dimension = aws_appautoscaling_target.service[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.service[0].service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = var.alb_target_value
    scale_in_cooldown  = var.scale_in_cooldown
    scale_out_cooldown = var.scale_out_cooldown

    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${split("/", var.target_group_arn)[1]}/${split("/", var.target_group_arn)[2]}/${split("/", var.target_group_arn)[3]}"
    }
  }
}

# ==============================================================================
# CODEDEPLOY (BLUE/GREEN DEPLOYMENT)
# ==============================================================================

resource "aws_codedeploy_app" "main" {
  count = var.enable_blue_green_deployment ? 1 : 0

  compute_platform = "ECS"
  name             = "${var.name_prefix}-${var.service_name}"

  tags = local.common_tags
}

resource "aws_iam_role" "codedeploy" {
  count = var.enable_blue_green_deployment ? 1 : 0

  name = "${var.name_prefix}-${var.service_name}-codedeploy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "codedeploy.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "codedeploy" {
  count = var.enable_blue_green_deployment ? 1 : 0

  role       = aws_iam_role.codedeploy[0].name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeDeployRoleForECS"
}

resource "aws_codedeploy_deployment_group" "main" {
  count = var.enable_blue_green_deployment ? 1 : 0

  app_name               = aws_codedeploy_app.main[0].name
  deployment_group_name  = "${var.name_prefix}-${var.service_name}-dg"
  deployment_config_name = var.deployment_config_name
  service_role_arn       = aws_iam_role.codedeploy[0].arn

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM"]
  }

  blue_green_deployment_config {
    deployment_ready_option {
      action_on_timeout = "CONTINUE_DEPLOYMENT"
    }

    terminate_blue_instances_on_deployment_success {
      action                           = "TERMINATE"
      termination_wait_time_in_minutes = var.termination_wait_time
    }
  }

  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "BLUE_GREEN"
  }

  ecs_service {
    cluster_name = var.create_cluster ? aws_ecs_cluster.main[0].name : var.cluster_name
    service_name = aws_ecs_service.main.name
  }

  dynamic "load_balancer_info" {
    for_each = var.enable_load_balancer && var.target_group_arn != null ? [1] : []
    content {
      target_group_pair_info {
        prod_traffic_route {
          listener_arns = []  # To be configured separately
        }

        target_group {
          name = split(":", var.target_group_arn)[5]
        }
      }
    }
  }

  tags = local.common_tags
}
