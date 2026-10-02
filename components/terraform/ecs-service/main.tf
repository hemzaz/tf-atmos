# An ECS service, its task definition and log group, modelled on a subset of
# Cloud Posse's aws-ecs-service component and its terraform-aws-ecs-alb-service-task
# / terraform-aws-ecs-container-definition modules: Fargate (default) or EC2,
# awsvpc networking only, an optional ALB target group and listener rule
# (lb.tf), optional target-tracking autoscaling (autoscaling.tf) and the
# execution/task roles (iam.tf). Deviations from Cloud Posse are noted beside
# the code; part 2 (service connect / discovery, CODE_DEPLOY blue-green,
# several target groups, volumes) is not here.
#
# The component creates no security group: security_group_ids are inputs, so
# ingress rules (and the "never 0.0.0.0/0 inbound" rule) live in the
# securitygroup instance that owns them.

locals {
  enabled = var.enabled
  prefix  = "${var.tags["Environment"]}-${var.name}"

  fargate        = var.launch_type == "FARGATE"
  log_group_name = "/ecs/${local.prefix}"
  # cluster/<name> is the last ARN segment; Application Auto Scaling's
  # resource id and the service's cluster both take the name.
  cluster_name = local.enabled ? element(split("/", var.ecs_cluster_arn), 1) : null

  lb_enabled          = local.enabled && var.load_balancer != null
  autoscaling_enabled = local.enabled && var.autoscaling != null

  # Container definitions (RegisterTaskDefinition's camelCase shape), sorted by
  # container name, with unset attributes dropped so the registered JSON matches
  # what ECS returns and plans stay clean.
  container_definitions = [
    for name in sort(keys(var.containers)) : {
      for k, v in {
        name              = name
        image             = var.containers[name].image
        cpu               = var.containers[name].cpu
        memory            = var.containers[name].memory
        memoryReservation = var.containers[name].memory_reservation
        essential         = var.containers[name].essential
        portMappings = length(var.containers[name].port_mappings) == 0 ? null : [
          for p in var.containers[name].port_mappings : {
            for pk, pv in {
              containerPort = p.container_port
              hostPort      = p.host_port
              protocol      = p.protocol
              name          = p.name
              appProtocol   = p.app_protocol
            } : pk => pv if pv != null
          }
        ]
        environment      = length(var.containers[name].environment) == 0 ? null : [for n, v in var.containers[name].environment : { name = n, value = v }]
        secrets          = length(var.containers[name].secrets) == 0 ? null : [for n, v in var.containers[name].secrets : { name = n, valueFrom = v }]
        command          = length(var.containers[name].command) == 0 ? null : var.containers[name].command
        entryPoint       = length(var.containers[name].entrypoint) == 0 ? null : var.containers[name].entrypoint
        workingDirectory = var.containers[name].working_directory
        user             = var.containers[name].user
        stopTimeout      = var.containers[name].stop_timeout

        # Sent only when true: false is ECS's default and is not returned, so
        # an explicit false would show a diff (and a new revision) every plan.
        readonlyRootFilesystem = var.containers[name].readonly_root_filesystem ? true : null
        linuxParameters        = try(var.containers[name].linux_parameters.init_process_enabled, false) ? { initProcessEnabled = true } : null

        healthCheck = var.containers[name].healthcheck == null ? null : {
          for hk, hv in {
            command     = var.containers[name].healthcheck.command
            interval    = var.containers[name].healthcheck.interval
            timeout     = var.containers[name].healthcheck.timeout
            retries     = var.containers[name].healthcheck.retries
            startPeriod = var.containers[name].healthcheck.start_period
          } : hk => hv if hv != null
        }

        logConfiguration = {
          logDriver = "awslogs"
          options = {
            "awslogs-group"         = local.log_group_name
            "awslogs-region"        = var.region
            "awslogs-stream-prefix" = coalesce(var.containers[name].log_stream_prefix, name)
          }
        }
      } : k => v if v != null
    }
  ]
}

resource "aws_cloudwatch_log_group" "this" {
  # checkov:skip=CKV_AWS_338:Retention mirrors the repo's other log groups (log_retention_days, default 90) and is a per-stack cost decision, not a module one.
  count = local.enabled ? 1 : 0

  name              = local.log_group_name
  kms_key_id        = var.log_kms_key_arn
  retention_in_days = var.log_retention_days

  tags = { Name = local.log_group_name }
}

resource "aws_ecs_task_definition" "this" {
  count = local.enabled ? 1 : 0

  family                   = local.prefix
  requires_compatibilities = [var.launch_type]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu == null ? null : tostring(var.task_cpu)
  memory                   = var.task_memory == null ? null : tostring(var.task_memory)
  execution_role_arn       = local.task_exec_role_arn
  task_role_arn            = local.task_role_arn
  container_definitions    = jsonencode(local.container_definitions)

  dynamic "runtime_platform" {
    for_each = var.runtime_platform == null ? [] : [var.runtime_platform]
    content {
      cpu_architecture        = runtime_platform.value.cpu_architecture
      operating_system_family = runtime_platform.value.operating_system_family
    }
  }

  dynamic "ephemeral_storage" {
    for_each = var.ephemeral_storage_size == null ? [] : [var.ephemeral_storage_size]
    content {
      size_in_gib = ephemeral_storage.value
    }
  }

  tags = { Name = local.prefix }

  # A task must not start before its roles can pull, log and read secrets.
  depends_on = [
    aws_iam_role_policy.task_execution,
    aws_iam_role_policy.task,
    aws_iam_role_policy.task_exec,
    aws_iam_role_policy_attachment.task,
  ]

  lifecycle {
    precondition {
      condition     = length(local.prefix) <= 255
      error_message = "The task definition family (<Environment>-<name>, \"${local.prefix}\") must be 255 characters or fewer."
    }
  }
}

locals {
  # Shared by both service resources below (one ignores desired_count).
  service_launch_type      = length(var.capacity_provider_strategies) == 0 ? var.launch_type : null
  service_platform_version = local.fargate ? var.platform_version : null
  service_load_balancers = local.lb_enabled ? [{
    target_group_arn = aws_lb_target_group.this[0].arn
    container_name   = var.load_balancer.container_name
    container_port   = var.load_balancer.container_port
  }] : []
  service_health_check_grace_period = local.lb_enabled ? var.health_check_grace_period_seconds : null
}

# Cloud Posse ecs-alb-service-task pattern: lifecycle.ignore_changes cannot be
# conditional, so the service is one of two resources. With autoscaling the
# desired count belongs to Application Auto Scaling and is ignored after
# creation; switching autoscaling on or off replaces the service.
resource "aws_ecs_service" "this" {
  count = local.enabled && !local.autoscaling_enabled ? 1 : 0

  name                               = local.prefix
  cluster                            = var.ecs_cluster_arn
  task_definition                    = aws_ecs_task_definition.this[0].arn
  desired_count                      = var.desired_count
  launch_type                        = local.service_launch_type
  platform_version                   = local.service_platform_version
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.deployment_maximum_percent
  enable_execute_command             = var.exec_enabled
  enable_ecs_managed_tags            = true
  propagate_tags                     = var.propagate_tags
  wait_for_steady_state              = var.wait_for_steady_state
  health_check_grace_period_seconds  = local.service_health_check_grace_period

  dynamic "capacity_provider_strategy" {
    for_each = var.capacity_provider_strategies
    content {
      capacity_provider = capacity_provider_strategy.value.capacity_provider
      weight            = capacity_provider_strategy.value.weight
      base              = capacity_provider_strategy.value.base
    }
  }

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = var.security_group_ids
    assign_public_ip = var.assign_public_ip
  }

  deployment_circuit_breaker {
    enable   = var.circuit_breaker_deployment_enabled
    rollback = var.circuit_breaker_rollback_enabled
  }

  dynamic "load_balancer" {
    for_each = local.service_load_balancers
    content {
      target_group_arn = load_balancer.value.target_group_arn
      container_name   = load_balancer.value.container_name
      container_port   = load_balancer.value.container_port
    }
  }

  tags = { Name = local.prefix }

  # The target group must be attached to the load balancer (by the listener
  # rule) before a service can register into it.
  depends_on = [aws_lb_listener_rule.this]
}

resource "aws_ecs_service" "autoscaled" {
  count = local.autoscaling_enabled ? 1 : 0

  name                               = local.prefix
  cluster                            = var.ecs_cluster_arn
  task_definition                    = aws_ecs_task_definition.this[0].arn
  desired_count                      = var.desired_count
  launch_type                        = local.service_launch_type
  platform_version                   = local.service_platform_version
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.deployment_maximum_percent
  enable_execute_command             = var.exec_enabled
  enable_ecs_managed_tags            = true
  propagate_tags                     = var.propagate_tags
  wait_for_steady_state              = var.wait_for_steady_state
  health_check_grace_period_seconds  = local.service_health_check_grace_period

  dynamic "capacity_provider_strategy" {
    for_each = var.capacity_provider_strategies
    content {
      capacity_provider = capacity_provider_strategy.value.capacity_provider
      weight            = capacity_provider_strategy.value.weight
      base              = capacity_provider_strategy.value.base
    }
  }

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = var.security_group_ids
    assign_public_ip = var.assign_public_ip
  }

  deployment_circuit_breaker {
    enable   = var.circuit_breaker_deployment_enabled
    rollback = var.circuit_breaker_rollback_enabled
  }

  dynamic "load_balancer" {
    for_each = local.service_load_balancers
    content {
      target_group_arn = load_balancer.value.target_group_arn
      container_name   = load_balancer.value.container_name
      container_port   = load_balancer.value.container_port
    }
  }

  tags = { Name = local.prefix }

  depends_on = [aws_lb_listener_rule.this]

  lifecycle {
    ignore_changes = [desired_count]
  }
}

locals {
  service = one(concat(aws_ecs_service.this, aws_ecs_service.autoscaled))
}
