# Web Service Component
# Containerized web service with load balancer, auto-scaling, and monitoring

locals {
  name_prefix = "${var.tenant}-${var.environment}"
  service_name = "${local.name_prefix}-${var.service_name}"
  
  common_tags = merge(var.tags, {
    Component = "web-service"
    Service   = var.service_name
    ManagedBy = "atmos"
    Environment = var.environment
  })
}

# Application Load Balancer
resource "aws_lb" "this" {
  count = var.load_balancer_enabled ? 1 : 0
  
  name               = "${local.service_name}-alb"
  internal           = var.internal_load_balancer
  load_balancer_type = "application"
  
  security_groups = [aws_security_group.alb[0].id]
  subnets        = var.public_subnet_ids
  
  enable_deletion_protection = var.deletion_protection
  
  access_logs {
    bucket  = var.access_logs_bucket
    prefix  = "alb/${local.service_name}"
    enabled = var.access_logs_enabled
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.service_name}-alb"
  })
}

# ALB Security Group
resource "aws_security_group" "alb" {
  count = var.load_balancer_enabled ? 1 : 0
  
  name_prefix = "${local.service_name}-alb-"
  vpc_id      = var.vpc_id
  description = "Security group for ${local.service_name} ALB"
  
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }
  
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }
  
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.service_name}-alb-sg"
  })
  
  lifecycle {
    create_before_destroy = true
  }
}

# Target Group
resource "aws_lb_target_group" "this" {
  count = var.load_balancer_enabled ? 1 : 0
  
  name     = "${local.service_name}-tg"
  port     = var.container_port
  protocol = "HTTP"
  vpc_id   = var.vpc_id
  
  health_check {
    enabled             = true
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

# ALB Listener
resource "aws_lb_listener" "this" {
  count = var.load_balancer_enabled ? 1 : 0
  
  load_balancer_arn = aws_lb.this[0].arn
  port              = var.certificate_arn != "" ? "443" : "80"
  protocol          = var.certificate_arn != "" ? "HTTPS" : "HTTP"
  
  dynamic "certificate_arn" {
    for_each = var.certificate_arn != "" ? [var.certificate_arn] : []
    content {
      certificate_arn = certificate_arn.value
    }
  }
  
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[0].arn
  }
}

# HTTP to HTTPS redirect
resource "aws_lb_listener" "redirect" {
  count = var.load_balancer_enabled && var.certificate_arn != "" ? 1 : 0
  
  load_balancer_arn = aws_lb.this[0].arn
  port              = "80"
  protocol          = "HTTP"
  
  default_action {
    type = "redirect"
    
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# ECS Cluster
resource "aws_ecs_cluster" "this" {
  name = "${local.service_name}-cluster"
  
  capacity_providers = var.capacity_providers
  
  default_capacity_provider_strategy {
    capacity_provider = var.default_capacity_provider
    weight           = 1
  }
  
  setting {
    name  = "containerInsights"
    value = var.container_insights_enabled ? "enabled" : "disabled"
  }
  
  tags = local.common_tags
}

# ECS Task Definition
resource "aws_ecs_task_definition" "this" {
  family                   = "${local.service_name}-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn           = aws_iam_role.task.arn
  
  container_definitions = jsonencode([
    {
      name      = var.service_name
      image     = var.container_image
      cpu       = var.task_cpu
      memory    = var.task_memory
      essential = true
      
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
        for key, valueFrom in var.secret_environment_variables : {
          name      = key
          valueFrom = valueFrom
        }
      ]
      
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.this.name
          awslogs-region        = data.aws_region.current.name
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
  launch_type     = "FARGATE"
  
  platform_version = var.platform_version
  
  network_configuration {
    security_groups  = [aws_security_group.service.id]
    subnets          = var.private_subnet_ids
    assign_public_ip = false
  }
  
  dynamic "load_balancer" {
    for_each = var.load_balancer_enabled ? [1] : []
    content {
      target_group_arn = aws_lb_target_group.this[0].arn
      container_name   = var.service_name
      container_port   = var.container_port
    }
  }
  
  deployment_configuration {
    maximum_percent         = var.deployment_maximum_percent
    minimum_healthy_percent = var.deployment_minimum_healthy_percent
    
    deployment_circuit_breaker {
      enable   = var.deployment_circuit_breaker_enabled
      rollback = var.deployment_circuit_breaker_rollback
    }
  }
  
  enable_execute_command = var.enable_execute_command
  
  tags = local.common_tags
  
  depends_on = [
    aws_lb_listener.this,
    aws_iam_role_policy_attachment.task_execution
  ]
}

# Service Security Group
resource "aws_security_group" "service" {
  name_prefix = "${local.service_name}-service-"
  vpc_id      = var.vpc_id
  description = "Security group for ${local.service_name} ECS service"
  
  ingress {
    description     = "Traffic from ALB"
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = var.load_balancer_enabled ? [aws_security_group.alb[0].id] : []
    cidr_blocks     = var.load_balancer_enabled ? [] : var.allowed_cidr_blocks
  }
  
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.service_name}-service-sg"
  })
  
  lifecycle {
    create_before_destroy = true
  }
}

# Auto Scaling Target
resource "aws_appautoscaling_target" "this" {
  count = var.auto_scaling_enabled ? 1 : 0
  
  max_capacity       = var.auto_scaling_max_capacity
  min_capacity       = var.auto_scaling_min_capacity
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.this.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
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
    
    scale_out_cooldown  = var.auto_scaling_scale_out_cooldown
    scale_in_cooldown   = var.auto_scaling_scale_in_cooldown
    disable_scale_in    = var.auto_scaling_disable_scale_in
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
    
    scale_out_cooldown  = var.auto_scaling_scale_out_cooldown
    scale_in_cooldown   = var.auto_scaling_scale_in_cooldown
    disable_scale_in    = var.auto_scaling_disable_scale_in
  }
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/${local.service_name}"
  retention_in_days = var.log_retention_days
  
  tags = local.common_tags
}

# Data sources
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}