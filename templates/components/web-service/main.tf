# Web Service Component
# Containerized web service on ECS Fargate with an Application Load Balancer,
# auto-scaling and CloudWatch logging.

locals {
  service_name  = "${var.tenant}-${var.environment}-${var.service_name}"
  https_enabled = var.certificate_arn != null

  # Provider default_tags carry Tenant/Account/Environment/ManagedBy from var.tags
  common_tags = {
    Component = "web-service"
    Service   = var.service_name
  }
}

data "aws_region" "current" {}

# Application Load Balancer
resource "aws_lb" "this" {
  count = var.load_balancer_enabled ? 1 : 0

  name               = "${local.service_name}-alb"
  internal           = var.internal_load_balancer
  load_balancer_type = "application"

  security_groups = [aws_security_group.alb[0].id]
  subnets         = var.internal_load_balancer ? var.private_subnet_ids : var.public_subnet_ids

  enable_deletion_protection = var.deletion_protection
  drop_invalid_header_fields = true

  dynamic "access_logs" {
    for_each = var.access_logs_enabled ? [var.access_logs_bucket] : []
    content {
      bucket  = access_logs.value
      prefix  = "alb/${local.service_name}"
      enabled = true
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.service_name}-alb"
  })

  lifecycle {
    precondition {
      condition     = length("${local.service_name}-alb") <= 32
      error_message = "The <tenant>-<environment>-<service_name> prefix must be at most 28 characters (ALB and target group names are limited to 32)."
    }
    precondition {
      condition     = !var.access_logs_enabled || var.access_logs_bucket != null
      error_message = "The access_logs_bucket is required when access_logs_enabled is true."
    }
  }
}

# ALB Security Group
resource "aws_security_group" "alb" {
  count = var.load_balancer_enabled ? 1 : 0

  name_prefix = "${local.service_name}-alb-"
  vpc_id      = var.vpc_id
  description = "Security group for ${local.service_name} ALB"

  tags = merge(local.common_tags, {
    Name = "${local.service_name}-alb-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  for_each = var.load_balancer_enabled && local.https_enabled ? toset(var.allowed_cidr_blocks) : toset([])

  security_group_id = aws_security_group.alb[0].id
  description       = "HTTPS from ${each.value}"
  cidr_ipv4         = each.value
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  for_each = var.load_balancer_enabled ? toset(var.allowed_cidr_blocks) : toset([])

  security_group_id = aws_security_group.alb[0].id
  description       = local.https_enabled ? "HTTP (redirect to HTTPS) from ${each.value}" : "HTTP from ${each.value}"
  cidr_ipv4         = each.value
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_service" {
  count = var.load_balancer_enabled ? 1 : 0

  security_group_id            = aws_security_group.alb[0].id
  description                  = "Traffic to the ECS service"
  referenced_security_group_id = aws_security_group.service.id
  from_port                    = var.container_port
  to_port                      = var.container_port
  ip_protocol                  = "tcp"
}

# Target Group
resource "aws_lb_target_group" "this" {
  count = var.load_balancer_enabled ? 1 : 0

  name        = "${local.service_name}-tg"
  port        = var.container_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  health_check {
    enabled             = var.health_check_enabled
    healthy_threshold   = var.health_check_healthy_threshold
    interval            = var.health_check_interval
    matcher             = var.health_check_matcher
    path                = var.health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = var.health_check_timeout
    unhealthy_threshold = var.health_check_unhealthy_threshold
  }

  tags = merge(local.common_tags, {
    Name = "${local.service_name}-tg"
  })
}

# Primary listener: HTTPS when a certificate is supplied, HTTP otherwise
resource "aws_lb_listener" "this" {
  count = var.load_balancer_enabled ? 1 : 0

  load_balancer_arn = aws_lb.this[0].arn
  port              = local.https_enabled ? 443 : 80
  protocol          = local.https_enabled ? "HTTPS" : "HTTP"
  certificate_arn   = var.certificate_arn
  ssl_policy        = local.https_enabled ? var.ssl_policy : null

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[0].arn
  }

  tags = local.common_tags
}

# HTTP to HTTPS redirect
resource "aws_lb_listener" "redirect" {
  count = var.load_balancer_enabled && local.https_enabled ? 1 : 0

  load_balancer_arn = aws_lb.this[0].arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  tags = local.common_tags
}

# ECS Cluster
resource "aws_ecs_cluster" "this" {
  name = "${local.service_name}-cluster"

  setting {
    name  = "containerInsights"
    value = var.container_insights_enabled ? "enhanced" : "disabled"
  }

  tags = local.common_tags
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = var.capacity_providers

  default_capacity_provider_strategy {
    capacity_provider = var.default_capacity_provider
    weight            = 1
  }
}

# ECS Task Definition
resource "aws_ecs_task_definition" "this" {
  family                   = "${local.service_name}-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.cpu_architecture
  }

  container_definitions = jsonencode([
    {
      name                   = var.service_name
      image                  = var.container_image
      essential              = true
      readonlyRootFilesystem = var.readonly_root_filesystem

      portMappings = [
        {
          containerPort = var.container_port
          protocol      = "tcp"
        }
      ]

      environment = [
        for key, value in var.environment_variables : {
          name  = key
          value = value
        }
      ]

      secrets = [
        for key, value_from in var.secret_environment_variables : {
          name      = key
          valueFrom = value_from
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.this.name
          awslogs-region        = data.aws_region.current.region
          awslogs-stream-prefix = "ecs"
        }
      }

      healthCheck = var.container_health_check_enabled ? {
        command     = var.container_health_check_command
        interval    = var.container_health_check_interval
        timeout     = var.container_health_check_timeout
        retries     = var.container_health_check_retries
        startPeriod = var.container_health_check_start_period
      } : null
    }
  ])

  tags = local.common_tags
}

# ECS Service
resource "aws_ecs_service" "this" {
  name            = "${local.service_name}-service"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count

  platform_version = var.platform_version

  capacity_provider_strategy {
    capacity_provider = var.default_capacity_provider
    weight            = 1
  }

  network_configuration {
    security_groups  = [aws_security_group.service.id]
    subnets          = var.private_subnet_ids
    assign_public_ip = false
  }

  dynamic "load_balancer" {
    for_each = var.load_balancer_enabled ? [aws_lb_target_group.this[0].arn] : []
    content {
      target_group_arn = load_balancer.value
      container_name   = var.service_name
      container_port   = var.container_port
    }
  }

  deployment_maximum_percent         = var.deployment_maximum_percent
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent

  deployment_circuit_breaker {
    enable   = var.deployment_circuit_breaker_enabled
    rollback = var.deployment_circuit_breaker_rollback
  }

  enable_execute_command = var.enable_execute_command
  propagate_tags         = "SERVICE"

  tags = local.common_tags

  # Auto scaling owns the task count once the service exists
  lifecycle {
    ignore_changes = [desired_count]
  }

  depends_on = [
    aws_lb_listener.this,
    aws_iam_role_policy_attachment.task_execution,
    aws_ecs_cluster_capacity_providers.this,
  ]
}

# Service Security Group
resource "aws_security_group" "service" {
  name_prefix = "${local.service_name}-service-"
  vpc_id      = var.vpc_id
  description = "Security group for ${local.service_name} ECS service"

  tags = merge(local.common_tags, {
    Name = "${local.service_name}-service-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "service_from_alb" {
  count = var.load_balancer_enabled ? 1 : 0

  security_group_id            = aws_security_group.service.id
  description                  = "Traffic from the ALB"
  referenced_security_group_id = aws_security_group.alb[0].id
  from_port                    = var.container_port
  to_port                      = var.container_port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "service_from_cidr" {
  for_each = var.load_balancer_enabled ? toset([]) : toset(var.allowed_cidr_blocks)

  security_group_id = aws_security_group.service.id
  description       = "Container port from ${each.value}"
  cidr_ipv4         = each.value
  from_port         = var.container_port
  to_port           = var.container_port
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "service" {
  for_each = toset(var.service_egress_cidr_blocks)

  security_group_id = aws_security_group.service.id
  description       = "Outbound traffic to ${each.value}"
  cidr_ipv4         = each.value
  ip_protocol       = "-1"
}

# Auto Scaling Target
resource "aws_appautoscaling_target" "this" {
  count = var.auto_scaling_enabled ? 1 : 0

  max_capacity       = var.auto_scaling_max_capacity
  min_capacity       = var.auto_scaling_min_capacity
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.this.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"

  tags = local.common_tags
}

# Auto Scaling Policy - CPU
resource "aws_appautoscaling_policy" "cpu" {
  count = var.auto_scaling_enabled ? 1 : 0

  name               = "${local.service_name}-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.this[0].resource_id
  scalable_dimension = aws_appautoscaling_target.this[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.this[0].service_namespace

  target_tracking_scaling_policy_configuration {
    target_value = var.auto_scaling_cpu_target

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }

    scale_out_cooldown = var.auto_scaling_scale_out_cooldown
    scale_in_cooldown  = var.auto_scaling_scale_in_cooldown
    disable_scale_in   = var.auto_scaling_disable_scale_in
  }
}

# Auto Scaling Policy - Memory
resource "aws_appautoscaling_policy" "memory" {
  count = var.auto_scaling_enabled && var.auto_scaling_memory_enabled ? 1 : 0

  name               = "${local.service_name}-memory-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.this[0].resource_id
  scalable_dimension = aws_appautoscaling_target.this[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.this[0].service_namespace

  target_tracking_scaling_policy_configuration {
    target_value = var.auto_scaling_memory_target

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }

    scale_out_cooldown = var.auto_scaling_scale_out_cooldown
    scale_in_cooldown  = var.auto_scaling_scale_in_cooldown
    disable_scale_in   = var.auto_scaling_disable_scale_in
  }
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/${local.service_name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.log_kms_key_arn

  tags = local.common_tags
}
