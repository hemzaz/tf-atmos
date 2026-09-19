# ECS Fargate Service Module - Main Configuration
# Version: 1.0.0

# ==============================================================================
# LOCAL VALUES
# ==============================================================================

locals {
  cluster_name   = var.create_cluster ? "${var.name_prefix}-${var.service_name}-cluster" : var.cluster_name
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

  cluster_id = var.create_cluster ? aws_ecs_cluster.main[0].id : var.cluster_name

  # container_definitions may be passed as a JSON string or as a list of objects.
  container_definitions_json = try(tostring(var.container_definitions), jsonencode(var.container_definitions))

  load_balancer_enabled       = var.enable_load_balancer && var.target_group_arn != null
  alb_target_tracking_enabled = var.enable_autoscaling && var.enable_alb_target_tracking && var.target_group_arn != null

  # Exactly one of aws_ecs_service.main / aws_ecs_service.autoscaled exists.
  service = var.enable_autoscaling ? aws_ecs_service.autoscaled[0] : aws_ecs_service.main[0]

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

data "aws_partition" "current" {}

data "aws_iam_policy_document" "ecs_tasks_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "codedeploy_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["codedeploy.amazonaws.com"]
    }
  }
}

# Task execution role (required for pulling images, writing logs)
resource "aws_iam_role" "execution" {
  count = var.execution_role_arn == null ? 1 : 0

  name = "${var.name_prefix}-${var.service_name}-execution"

  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "execution" {
  count = var.execution_role_arn == null ? 1 : 0

  role       = aws_iam_role.execution[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Additional policy for Secrets Manager and SSM Parameter Store
data "aws_iam_policy_document" "execution_secrets" {
  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "ssm:GetParameters",
      "kms:Decrypt"
    ]
    resources = values(var.secrets)
  }
}

resource "aws_iam_role_policy" "execution_secrets" {
  count = var.execution_role_arn == null && length(var.secrets) > 0 ? 1 : 0

  name = "${var.name_prefix}-${var.service_name}-execution-secrets"
  role = aws_iam_role.execution[0].id

  policy = data.aws_iam_policy_document.execution_secrets.json
}

# Task role (for application permissions)
resource "aws_iam_role" "task" {
  count = var.task_role_arn == null ? 1 : 0

  name = "${var.name_prefix}-${var.service_name}-task"

  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json

  tags = local.common_tags
}

# Attach custom policies to task role
resource "aws_iam_role_policy_attachment" "task" {
  for_each = toset(var.task_role_arn == null ? var.task_role_policies : [])

  role       = aws_iam_role.task[0].name
  policy_arn = each.value
}

# Policy for ECS Exec
data "aws_iam_policy_document" "task_exec" {
  statement {
    effect = "Allow"
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "task_exec" {
  count = var.task_role_arn == null && var.enable_execute_command ? 1 : 0

  name = "${var.name_prefix}-${var.service_name}-task-exec"
  role = aws_iam_role.task[0].id

  policy = data.aws_iam_policy_document.task_exec.json
}

# Policy for X-Ray
data "aws_iam_policy_document" "task_xray" {
  statement {
    effect = "Allow"
    actions = [
      "xray:PutTraceSegments",
      "xray:PutTelemetryRecords"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "task_xray" {
  count = var.task_role_arn == null && var.enable_xray_tracing ? 1 : 0

  name = "${var.name_prefix}-${var.service_name}-task-xray"
  role = aws_iam_role.task[0].id

  policy = data.aws_iam_policy_document.task_xray.json
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

  container_definitions = local.container_definitions_json

  runtime_platform {
    operating_system_family = var.runtime_platform.operating_system_family
    cpu_architecture        = var.runtime_platform.cpu_architecture
  }

  # 20 GiB is the Fargate default; the API only accepts explicit values of 21-200.
  dynamic "ephemeral_storage" {
    for_each = var.ephemeral_storage_size_gb > 20 ? [1] : []
    content {
      size_in_gib = var.ephemeral_storage_size_gb
    }
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

  # failure_threshold is deprecated (AWS always uses 1).
  health_check_custom_config {}

  tags = local.common_tags
}

# ==============================================================================
# ECS SERVICE
# ==============================================================================

# lifecycle.ignore_changes must be static, so the service is declared twice:
# "main" when autoscaling is disabled (desired_count is managed by Terraform) and
# "autoscaled" when it is enabled (desired_count is owned by Application Auto
# Scaling after creation). Use local.service to reference whichever exists.
resource "aws_ecs_service" "main" {
  count = var.enable_autoscaling ? 0 : 1

  name            = var.service_name
  cluster         = local.cluster_id
  task_definition = aws_ecs_task_definition.main.arn
  desired_count   = var.desired_count
  launch_type     = var.enable_fargate_spot ? null : "FARGATE"

  enable_execute_command = var.enable_execute_command
  force_new_deployment   = var.force_new_deployment

  deployment_maximum_percent         = var.deployment_maximum_percent
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent

  # The circuit breaker is only supported by the ECS deployment controller.
  dynamic "deployment_circuit_breaker" {
    for_each = var.enable_blue_green_deployment ? [] : [1]
    content {
      enable   = var.enable_deployment_circuit_breaker
      rollback = var.enable_deployment_circuit_breaker
    }
  }

  network_configuration {
    subnets          = var.subnet_ids
    assign_public_ip = var.assign_public_ip
    security_groups  = length(var.security_group_ids) > 0 ? var.security_group_ids : [aws_security_group.service[0].id]
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
    for_each = local.load_balancer_enabled ? [1] : []
    content {
      target_group_arn = var.target_group_arn
      container_name   = var.container_name
      container_port   = var.container_port
    }
  }

  health_check_grace_period_seconds = local.load_balancer_enabled ? var.health_check_grace_period_seconds : null

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

  depends_on = [
    aws_iam_role_policy_attachment.execution
  ]
}

resource "aws_ecs_service" "autoscaled" {
  count = var.enable_autoscaling ? 1 : 0

  name            = var.service_name
  cluster         = local.cluster_id
  task_definition = aws_ecs_task_definition.main.arn
  desired_count   = var.desired_count
  launch_type     = var.enable_fargate_spot ? null : "FARGATE"

  enable_execute_command = var.enable_execute_command
  force_new_deployment   = var.force_new_deployment

  deployment_maximum_percent         = var.deployment_maximum_percent
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent

  # The circuit breaker is only supported by the ECS deployment controller.
  dynamic "deployment_circuit_breaker" {
    for_each = var.enable_blue_green_deployment ? [] : [1]
    content {
      enable   = var.enable_deployment_circuit_breaker
      rollback = var.enable_deployment_circuit_breaker
    }
  }

  network_configuration {
    subnets          = var.subnet_ids
    assign_public_ip = var.assign_public_ip
    security_groups  = length(var.security_group_ids) > 0 ? var.security_group_ids : [aws_security_group.service[0].id]
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
    for_each = local.load_balancer_enabled ? [1] : []
    content {
      target_group_arn = var.target_group_arn
      container_name   = var.container_name
      container_port   = var.container_port
    }
  }

  health_check_grace_period_seconds = local.load_balancer_enabled ? var.health_check_grace_period_seconds : null

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

  depends_on = [
    aws_iam_role_policy_attachment.execution
  ]

  lifecycle {
    ignore_changes = [desired_count]
  }
}

# ==============================================================================
# AUTO-SCALING
# ==============================================================================

resource "aws_appautoscaling_target" "service" {
  count = var.enable_autoscaling ? 1 : 0

  max_capacity       = var.autoscaling_max_capacity
  min_capacity       = var.autoscaling_min_capacity
  resource_id        = "service/${local.cluster_name}/${local.service.name}"
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
# ALBRequestCountPerTarget needs "<lb arn suffix>/<target group arn suffix>";
# the load balancer part cannot be derived from the target group ARN alone.
data "aws_lb_target_group" "alb" {
  count = local.alb_target_tracking_enabled ? 1 : 0

  arn = var.target_group_arn
}

data "aws_lb" "alb" {
  count = local.alb_target_tracking_enabled ? 1 : 0

  arn = one(data.aws_lb_target_group.alb[0].load_balancer_arns)
}

resource "aws_appautoscaling_policy" "alb" {
  count = local.alb_target_tracking_enabled ? 1 : 0

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
      resource_label         = "${data.aws_lb.alb[0].arn_suffix}/${data.aws_lb_target_group.alb[0].arn_suffix}"
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

  assume_role_policy = data.aws_iam_policy_document.codedeploy_assume_role.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "codedeploy" {
  count = var.enable_blue_green_deployment ? 1 : 0

  role       = aws_iam_role.codedeploy[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AWSCodeDeployRoleForECS"
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
    service_name = local.service.name
  }

  dynamic "load_balancer_info" {
    for_each = local.load_balancer_enabled ? [1] : []
    content {
      target_group_pair_info {
        prod_traffic_route {
          listener_arns = [] # To be configured separately
        }

        # target_group takes the name: arn:...:targetgroup/<name>/<id>
        target_group {
          name = split("/", var.target_group_arn)[1]
        }
      }
    }
  }

  tags = local.common_tags
}
