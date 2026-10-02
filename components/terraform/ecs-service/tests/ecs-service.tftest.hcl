# Mock-provider tests: no AWS credentials, no network. Run from the component
# directory with `terraform init -backend=false && terraform test`.

mock_provider "aws" {
  override_during = plan

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:us-east-1:123456789012:log-group:/ecs/test-web"
    }
  }

  mock_resource "aws_ecs_task_definition" {
    defaults = {
      arn = "arn:aws:ecs:us-east-1:123456789012:task-definition/test-web:1"
    }
  }

  mock_resource "aws_lb_target_group" {
    defaults = {
      arn        = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/test-web/0123456789abcdef"
      arn_suffix = "targetgroup/test-web/0123456789abcdef"
    }
  }

  # launch_type and platform_version are optional+computed: when the
  # configuration leaves them null the mock fills these placeholders, which
  # the assertions read as "not set".
  mock_resource "aws_ecs_service" {
    defaults = {
      arn              = "arn:aws:ecs:us-east-1:123456789012:service/test-cluster/test-web"
      launch_type      = "UNSET"
      platform_version = "UNSET"
    }
  }
}

override_resource {
  override_during = plan
  target          = aws_iam_role.task_execution[0]
  values          = { arn = "arn:aws:iam::123456789012:role/test-web-task-execution", id = "test-web-task-execution" }
}

override_resource {
  override_during = plan
  target          = aws_iam_role.task[0]
  values          = { arn = "arn:aws:iam::123456789012:role/test-web-task", id = "test-web-task", name = "test-web-task" }
}

variables {
  region          = "us-east-1"
  name            = "web"
  ecs_cluster_arn = "arn:aws:ecs:us-east-1:123456789012:cluster/test-cluster"
  log_kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"
  tags = {
    Environment = "test"
    Tenant      = "fnx"
    ManagedBy   = "Terraform"
  }

  task_cpu           = 512
  task_memory        = 1024
  subnet_ids         = ["subnet-0aaa", "subnet-0bbb"]
  security_group_ids = ["sg-0123"]
  desired_count      = 2

  containers = {
    app = {
      image         = "123456789012.dkr.ecr.us-east-1.amazonaws.com/web:1.0"
      port_mappings = [{ container_port = 8080, name = "http", app_protocol = "http" }]
      environment = {
        ENVIRONMENT = "test"
        APP_PORT    = "8080"
      }
      secrets = {
        DATABASE_PASSWORD = "arn:aws:secretsmanager:us-east-1:123456789012:secret:test/db-AbC123:password::"
        API_TOKEN         = "arn:aws:ssm:us-east-1:123456789012:parameter/test/api-token"
      }
      healthcheck = {
        command      = ["CMD-SHELL", "curl -f http://localhost:8080/health || exit 1"]
        start_period = 60
      }
      linux_parameters = { init_process_enabled = true }
    }
    log-router = {
      image                    = "public.ecr.aws/aws-observability/aws-for-fluent-bit:stable"
      essential                = false
      memory_reservation       = 50
      readonly_root_filesystem = false
      log_stream_prefix        = "firelens"
    }
  }

  task_policy_json    = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"s3:GetObject\",\"Resource\":\"arn:aws:s3:::assets/*\"}]}"
  secrets_kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/99999999-8888-7777-6666-555555555555"

  load_balancer = {
    listener_arn   = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/test-webapp-alb/50dc6c495c0c9188/f2f7dc8efc522ab2"
    vpc_id         = "vpc-0abc"
    container_name = "app"
    container_port = 8080
    priority       = 100
    host_headers   = ["app.example.com"]
    path_patterns  = ["/api/*"]
    health_check   = { path = "/health" }
  }

  autoscaling = {
    min_capacity                 = 2
    max_capacity                 = 10
    cpu_utilization_target       = 70
    alb_request_count_per_target = 1000
  }
}

run "fargate_service_with_lb_and_autoscaling" {
  command = plan

  assert {
    condition     = length(aws_ecs_service.this) == 0 && length(aws_ecs_service.autoscaled) == 1
    error_message = "With autoscaling the service is the desired_count-ignoring resource."
  }

  assert {
    condition = (
      aws_ecs_service.autoscaled[0].name == "test-web"
      && aws_ecs_service.autoscaled[0].cluster == var.ecs_cluster_arn
      && aws_ecs_service.autoscaled[0].launch_type == "FARGATE"
      && aws_ecs_service.autoscaled[0].platform_version == "LATEST"
      && aws_ecs_service.autoscaled[0].desired_count == 2
      && aws_ecs_service.autoscaled[0].task_definition == "arn:aws:ecs:us-east-1:123456789012:task-definition/test-web:1"
    )
    error_message = "The service is <Environment>-<name> on the given cluster, FARGATE LATEST, running the task definition."
  }

  assert {
    condition = (
      aws_ecs_service.autoscaled[0].deployment_circuit_breaker[0].enable
      && aws_ecs_service.autoscaled[0].deployment_circuit_breaker[0].rollback
      && aws_ecs_service.autoscaled[0].deployment_minimum_healthy_percent == 100
      && aws_ecs_service.autoscaled[0].deployment_maximum_percent == 200
      && aws_ecs_service.autoscaled[0].propagate_tags == "SERVICE"
      && aws_ecs_service.autoscaled[0].wait_for_steady_state == false
      && aws_ecs_service.autoscaled[0].enable_execute_command == false
      && aws_ecs_service.autoscaled[0].enable_ecs_managed_tags
    )
    error_message = "Defaults: circuit breaker with rollback, 100/200 percent, propagate SERVICE tags, no steady-state wait, no ECS Exec."
  }

  assert {
    condition = (
      aws_ecs_service.autoscaled[0].network_configuration[0].subnets == toset(["subnet-0aaa", "subnet-0bbb"])
      && aws_ecs_service.autoscaled[0].network_configuration[0].security_groups == toset(["sg-0123"])
      && aws_ecs_service.autoscaled[0].network_configuration[0].assign_public_ip == false
    )
    error_message = "awsvpc network configuration with the given subnets and security groups and no public IP."
  }

  assert {
    condition = (
      aws_ecs_service.autoscaled[0].health_check_grace_period_seconds == 60
      && one(aws_ecs_service.autoscaled[0].load_balancer).container_name == "app"
      && one(aws_ecs_service.autoscaled[0].load_balancer).container_port == 8080
      && one(aws_ecs_service.autoscaled[0].load_balancer).target_group_arn == aws_lb_target_group.this[0].arn
    )
    error_message = "The service registers app:8080 into its target group, with a health check grace period."
  }

  assert {
    condition = (
      aws_lb_target_group.this[0].name == "test-web"
      && aws_lb_target_group.this[0].target_type == "ip"
      && aws_lb_target_group.this[0].port == 8080
      && aws_lb_target_group.this[0].protocol == "HTTP"
      && aws_lb_target_group.this[0].vpc_id == "vpc-0abc"
      && aws_lb_target_group.this[0].health_check[0].path == "/health"
      && aws_lb_target_group.this[0].health_check[0].matcher == "200-399"
    )
    error_message = "The target group is <Environment>-<name>, ip targets on the container port, with the health check inputs."
  }

  assert {
    condition = (
      aws_lb_listener_rule.this[0].listener_arn == var.load_balancer.listener_arn
      && aws_lb_listener_rule.this[0].priority == 100
      && aws_lb_listener_rule.this[0].action[0].type == "forward"
      && aws_lb_listener_rule.this[0].action[0].target_group_arn == aws_lb_target_group.this[0].arn
      && length(aws_lb_listener_rule.this[0].condition) == 2
    )
    error_message = "The listener rule forwards to the target group at the given priority, with host and path conditions."
  }

  assert {
    condition = (
      aws_appautoscaling_target.this[0].resource_id == "service/test-cluster/test-web"
      && aws_appautoscaling_target.this[0].scalable_dimension == "ecs:service:DesiredCount"
      && aws_appautoscaling_target.this[0].min_capacity == 2
      && aws_appautoscaling_target.this[0].max_capacity == 10
      && keys(aws_appautoscaling_policy.this) == ["alb-requests", "cpu"]
    )
    error_message = "The scalable target is service/<cluster>/<service>; one target-tracking policy per set target."
  }

  assert {
    condition = (
      aws_appautoscaling_policy.this["cpu"].target_tracking_scaling_policy_configuration[0].predefined_metric_specification[0].predefined_metric_type == "ECSServiceAverageCPUUtilization"
      && aws_appautoscaling_policy.this["cpu"].target_tracking_scaling_policy_configuration[0].target_value == 70
      && aws_appautoscaling_policy.this["alb-requests"].target_tracking_scaling_policy_configuration[0].predefined_metric_specification[0].predefined_metric_type == "ALBRequestCountPerTarget"
      && aws_appautoscaling_policy.this["alb-requests"].target_tracking_scaling_policy_configuration[0].predefined_metric_specification[0].resource_label == "app/test-webapp-alb/50dc6c495c0c9188/targetgroup/test-web/0123456789abcdef"
      && aws_appautoscaling_policy.this["alb-requests"].target_tracking_scaling_policy_configuration[0].scale_in_cooldown == 300
      && aws_appautoscaling_policy.this["alb-requests"].target_tracking_scaling_policy_configuration[0].scale_out_cooldown == 60
    )
    error_message = "CPU and ALB request-count tracking; the request-count label is app/<lb>/<id>/targetgroup/<tg>/<id>."
  }

  assert {
    condition = (
      aws_ecs_task_definition.this[0].family == "test-web"
      && aws_ecs_task_definition.this[0].requires_compatibilities == toset(["FARGATE"])
      && aws_ecs_task_definition.this[0].network_mode == "awsvpc"
      && aws_ecs_task_definition.this[0].cpu == "512"
      && aws_ecs_task_definition.this[0].memory == "1024"
      && length(aws_ecs_task_definition.this[0].runtime_platform) == 0
      && length(aws_ecs_task_definition.this[0].ephemeral_storage) == 0
    )
    error_message = "A FARGATE awsvpc task definition, family <Environment>-<name>, sized by task_cpu/task_memory."
  }

  assert {
    condition = (
      aws_cloudwatch_log_group.this[0].name == "/ecs/test-web"
      && aws_cloudwatch_log_group.this[0].kms_key_id == var.log_kms_key_arn
      && aws_cloudwatch_log_group.this[0].retention_in_days == 90
    )
    error_message = "The log group is /ecs/<Environment>-<name>, KMS-encrypted, 90 days."
  }

  assert {
    condition = (
      output.service_name == "test-web"
      && output.service_arn == "arn:aws:ecs:us-east-1:123456789012:service/test-cluster/test-web"
      && output.task_definition_family == "test-web"
      && output.execution_role_arn == "arn:aws:iam::123456789012:role/test-web-task-execution"
      && output.task_role_arn == "arn:aws:iam::123456789012:role/test-web-task"
      && output.target_group_arn == aws_lb_target_group.this[0].arn
      && output.log_group_name == "/ecs/test-web"
    )
    error_message = "Outputs expose the service, task definition, roles, target group and log group."
  }
}

run "container_definitions_drop_unset_attributes" {
  command = plan

  assert {
    condition     = [for c in jsondecode(aws_ecs_task_definition.this[0].container_definitions) : c.name] == ["app", "log-router"]
    error_message = "Containers are sorted by name."
  }

  assert {
    condition = jsondecode(aws_ecs_task_definition.this[0].container_definitions)[0] == {
      name         = "app"
      image        = "123456789012.dkr.ecr.us-east-1.amazonaws.com/web:1.0"
      essential    = true
      portMappings = [{ containerPort = 8080, protocol = "tcp", name = "http", appProtocol = "http" }]
      environment  = [{ name = "APP_PORT", value = "8080" }, { name = "ENVIRONMENT", value = "test" }]
      secrets = [
        { name = "API_TOKEN", valueFrom = "arn:aws:ssm:us-east-1:123456789012:parameter/test/api-token" },
        { name = "DATABASE_PASSWORD", valueFrom = "arn:aws:secretsmanager:us-east-1:123456789012:secret:test/db-AbC123:password::" },
      ]
      readonlyRootFilesystem = true
      linuxParameters        = { initProcessEnabled = true }
      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:8080/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/test-web"
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "app"
        }
      }
    }
    error_message = "The app container JSON has exactly the set attributes (no nulls, no empty lists, host port omitted)."
  }

  assert {
    condition = jsondecode(aws_ecs_task_definition.this[0].container_definitions)[1] == {
      name              = "log-router"
      image             = "public.ecr.aws/aws-observability/aws-for-fluent-bit:stable"
      essential         = false
      memoryReservation = 50
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/test-web"
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "firelens"
        }
      }
    }
    error_message = "A false readonly_root_filesystem, false init process, no ports/env/secrets/healthcheck are omitted, not sent as false/empty."
  }
}

run "created_roles_and_trusts" {
  command = plan

  assert {
    condition = jsondecode(aws_iam_role.task_execution[0].assume_role_policy).Statement == [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Condition = { StringEquals = { "aws:SourceAccount" = "123456789012" } }
    }]
    error_message = "The execution role trusts ECS tasks with aws:SourceAccount only (no SourceArn)."
  }

  assert {
    condition = jsondecode(aws_iam_role.task[0].assume_role_policy).Statement == [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Condition = {
        StringEquals = { "aws:SourceAccount" = "123456789012" }
        ArnLike      = { "aws:SourceArn" = "arn:aws:ecs:us-east-1:123456789012:*" }
      }
    }]
    error_message = "The task role trusts ECS tasks with aws:SourceAccount and aws:SourceArn arn:aws:ecs:<region>:<account>:*."
  }

  assert {
    condition = (
      aws_iam_role.task_execution[0].name == "test-web-task-execution"
      && aws_iam_role.task[0].name == "test-web-task"
      && aws_iam_role_policy.task[0].policy == var.task_policy_json
      && length(aws_iam_role_policy.task_exec) == 0
      && aws_ecs_task_definition.this[0].execution_role_arn == "arn:aws:iam::123456789012:role/test-web-task-execution"
      && aws_ecs_task_definition.this[0].task_role_arn == "arn:aws:iam::123456789012:role/test-web-task"
    )
    error_message = "Both roles are created (<Environment>-<name>-task-execution, -task) and set on the task definition; no exec policy without exec_enabled."
  }

  assert {
    condition = (
      one([for s in jsondecode(aws_iam_role_policy.task_execution[0].policy).Statement : s.Resource if s.Sid == "SecretsManager"]) == ["arn:aws:secretsmanager:us-east-1:123456789012:secret:test/db-AbC123"]
      && one([for s in jsondecode(aws_iam_role_policy.task_execution[0].policy).Statement : s.Resource if s.Sid == "SSMParameters"]) == ["arn:aws:ssm:us-east-1:123456789012:parameter/test/api-token"]
      && one([for s in jsondecode(aws_iam_role_policy.task_execution[0].policy).Statement : s.Resource if s.Sid == "Logs"]) == "arn:aws:logs:us-east-1:123456789012:log-group:/ecs/test-web:log-stream:*"
      && one([for s in jsondecode(aws_iam_role_policy.task_execution[0].policy).Statement : s.Resource if s.Sid == "ECRPull"]) == ["*"]
    )
    error_message = "The execution role reads exactly the secret ARNs (json-key tail dropped) and parameters, and logs only to the component log group."
  }

  assert {
    condition = one([for s in jsondecode(aws_iam_role_policy.task_execution[0].policy).Statement : s if s.Sid == "SecretsKMS"]) == {
      Sid       = "SecretsKMS"
      Effect    = "Allow"
      Action    = ["kms:Decrypt"]
      Resource  = "arn:aws:kms:us-east-1:123456789012:key/99999999-8888-7777-6666-555555555555"
      Condition = { StringEquals = { "kms:ViaService" = ["secretsmanager.us-east-1.amazonaws.com", "ssm.us-east-1.amazonaws.com"] } }
    }
    error_message = "kms:Decrypt on secrets_kms_key_arn only through Secrets Manager and SSM."
  }
}

run "given_roles_are_used_not_created" {
  command = plan

  variables {
    task_exec_role_arn = "arn:aws:iam::123456789012:role/shared-execution"
    task_role_arn      = "arn:aws:iam::123456789012:role/shared-task"
    task_policy_json   = null
  }

  assert {
    condition = (
      length(aws_iam_role.task_execution) == 0 && length(aws_iam_role_policy.task_execution) == 0
      && length(aws_iam_role.task) == 0 && length(aws_iam_role_policy.task) == 0
      && aws_ecs_task_definition.this[0].execution_role_arn == "arn:aws:iam::123456789012:role/shared-execution"
      && aws_ecs_task_definition.this[0].task_role_arn == "arn:aws:iam::123456789012:role/shared-task"
      && output.execution_role_arn == "arn:aws:iam::123456789012:role/shared-execution"
      && output.task_role_arn == "arn:aws:iam::123456789012:role/shared-task"
    )
    error_message = "task_exec_role_arn and task_role_arn are used as given; no roles are created."
  }
}

run "no_task_role_without_policies" {
  command = plan

  variables {
    task_policy_json = null
  }

  assert {
    condition     = length(aws_iam_role.task) == 0 && aws_ecs_task_definition.this[0].task_role_arn == null && output.task_role_arn == null
    error_message = "Without task policies or exec the tasks get no task role."
  }
}

run "exec_enabled_grants_ssmmessages" {
  command = plan

  variables {
    task_policy_json = null
    exec_enabled     = true
    exec_kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
  }

  assert {
    condition = (
      aws_ecs_service.autoscaled[0].enable_execute_command
      && length(aws_iam_role.task) == 1
      && [for s in jsondecode(aws_iam_role_policy.task_exec[0].policy).Statement : s.Sid] == ["SSMMessages", "ExecKMS"]
      && one([for s in jsondecode(aws_iam_role_policy.task_exec[0].policy).Statement : s.Resource if s.Sid == "ExecKMS"]) == var.exec_kms_key_arn
    )
    error_message = "exec_enabled turns on ECS Exec and creates the task role with ssmmessages and the exec key."
  }
}

run "ec2_with_capacity_providers" {
  command = plan

  variables {
    launch_type                  = "EC2"
    task_cpu                     = null
    task_memory                  = null
    capacity_provider_strategies = [{ capacity_provider = "test-cluster-capacity-provider", base = 1 }]
    load_balancer                = null
    autoscaling                  = null
    containers = {
      app = {
        image         = "123456789012.dkr.ecr.us-east-1.amazonaws.com/web:1.0"
        memory        = 512
        cpu           = 256
        port_mappings = [{ container_port = 8080, host_port = 8080 }]
      }
    }
    runtime_platform = { cpu_architecture = "ARM64" }
  }

  assert {
    condition = (
      length(aws_ecs_service.this) == 1 && length(aws_ecs_service.autoscaled) == 0
      && aws_ecs_service.this[0].launch_type == "UNSET"
      && aws_ecs_service.this[0].platform_version == "UNSET"
      && aws_ecs_service.this[0].health_check_grace_period_seconds == null
      && length(aws_ecs_service.this[0].load_balancer) == 0
      && one(aws_ecs_service.this[0].capacity_provider_strategy).capacity_provider == "test-cluster-capacity-provider"
      && one(aws_ecs_service.this[0].capacity_provider_strategy).weight == 1
      && one(aws_ecs_service.this[0].capacity_provider_strategy).base == 1
    )
    error_message = "A capacity provider strategy replaces launch_type; no platform version on EC2, no LB settings without a load balancer."
  }

  assert {
    condition = (
      aws_ecs_task_definition.this[0].requires_compatibilities == toset(["EC2"])
      && aws_ecs_task_definition.this[0].cpu == null
      && aws_ecs_task_definition.this[0].memory == null
      && aws_ecs_task_definition.this[0].runtime_platform[0].cpu_architecture == "ARM64"
      && aws_ecs_task_definition.this[0].runtime_platform[0].operating_system_family == "LINUX"
      && jsondecode(aws_ecs_task_definition.this[0].container_definitions)[0].portMappings == [{ containerPort = 8080, hostPort = 8080, protocol = "tcp" }]
      && jsondecode(aws_ecs_task_definition.this[0].container_definitions)[0].memory == 512
    )
    error_message = "An EC2 task definition may leave the task size unset (containers size themselves) and take a runtime platform."
  }

  assert {
    condition     = length(aws_lb_target_group.this) == 0 && length(aws_lb_listener_rule.this) == 0 && length(aws_appautoscaling_target.this) == 0 && output.target_group_arn == null
    error_message = "No load balancer or autoscaling resources when unset."
  }
}

run "fargate_ephemeral_storage_and_launch_type" {
  command = plan

  variables {
    ephemeral_storage_size = 50
    autoscaling            = null
    assign_public_ip       = true
  }

  assert {
    condition = (
      aws_ecs_task_definition.this[0].ephemeral_storage[0].size_in_gib == 50
      && aws_ecs_service.this[0].launch_type == "FARGATE"
      && aws_ecs_service.this[0].network_configuration[0].assign_public_ip
      && length(aws_ecs_service.this[0].capacity_provider_strategy) == 0
    )
    error_message = "ephemeral_storage_size sets the task's ephemeral storage; without capacity providers the service uses launch_type."
  }
}

run "disabled_creates_nothing" {
  command = plan

  variables {
    enabled = false
  }

  assert {
    condition = (
      length(aws_ecs_task_definition.this) == 0 && length(aws_ecs_service.this) == 0 && length(aws_ecs_service.autoscaled) == 0
      && length(aws_cloudwatch_log_group.this) == 0 && length(aws_iam_role.task_execution) == 0 && length(aws_iam_role.task) == 0
      && length(aws_lb_target_group.this) == 0 && length(aws_appautoscaling_target.this) == 0
      && output.service_name == null && output.execution_role_arn == null
    )
    error_message = "enabled = false creates no resources."
  }
}

# Negative validations.

run "fargate_rejects_an_unsupported_cpu_memory_pair" {
  command = plan

  variables {
    task_cpu    = 512
    task_memory = 512
  }

  expect_failures = [var.task_memory]
}

run "fargate_rejects_an_unsupported_cpu" {
  command = plan

  variables {
    task_cpu = 768
  }

  expect_failures = [var.task_cpu]
}

run "fargate_requires_a_task_size" {
  command = plan

  variables {
    task_cpu    = null
    task_memory = null
  }

  # task_memory's and containers' rules read var.task_cpu / var.task_memory, so
  # Terraform skips them once task_cpu has failed.
  expect_failures = [var.task_cpu]
}

run "load_balancer_rejects_a_port_the_container_does_not_map" {
  command = plan

  variables {
    load_balancer = {
      listener_arn   = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/test-webapp-alb/50dc6c495c0c9188/f2f7dc8efc522ab2"
      vpc_id         = "vpc-0abc"
      container_name = "app"
      container_port = 9090
      priority       = 100
      path_patterns  = ["/*"]
    }
  }

  expect_failures = [var.load_balancer]
}

run "load_balancer_rejects_an_unknown_container" {
  command = plan

  variables {
    load_balancer = {
      listener_arn   = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/test-webapp-alb/50dc6c495c0c9188/f2f7dc8efc522ab2"
      vpc_id         = "vpc-0abc"
      container_name = "web"
      container_port = 8080
      priority       = 100
      path_patterns  = ["/*"]
    }
  }

  expect_failures = [var.load_balancer]
}

run "load_balancer_needs_a_condition" {
  command = plan

  variables {
    load_balancer = {
      listener_arn   = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/test-webapp-alb/50dc6c495c0c9188/f2f7dc8efc522ab2"
      vpc_id         = "vpc-0abc"
      container_name = "app"
      container_port = 8080
      priority       = 100
    }
    autoscaling = null
  }

  expect_failures = [var.load_balancer]
}

run "secrets_reject_an_arn_without_the_suffix" {
  command = plan

  variables {
    containers = {
      app = {
        image         = "web:1.0"
        port_mappings = [{ container_port = 8080 }]
        secrets       = { DATABASE_PASSWORD = "arn:aws:secretsmanager:us-east-1:123456789012:secret:test/db" }
      }
    }
  }

  expect_failures = [var.containers]
}

run "secrets_reject_a_name" {
  command = plan

  variables {
    containers = {
      app = {
        image         = "web:1.0"
        port_mappings = [{ container_port = 8080 }]
        secrets       = { DATABASE_PASSWORD = "test/db" }
      }
    }
  }

  expect_failures = [var.containers]
}

run "port_mappings_reject_a_different_host_port" {
  command = plan

  variables {
    containers = {
      app = {
        image         = "web:1.0"
        port_mappings = [{ container_port = 8080, host_port = 80 }]
      }
    }
  }

  expect_failures = [var.containers]
}

run "containers_need_an_essential_container" {
  command = plan

  variables {
    load_balancer = null
    autoscaling   = null
    containers    = { app = { image = "web:1.0", essential = false } }
  }

  expect_failures = [var.containers]
}

run "autoscaling_request_count_needs_a_load_balancer" {
  command = plan

  variables {
    load_balancer = null
  }

  expect_failures = [var.autoscaling]
}

run "autoscaling_needs_a_target" {
  command = plan

  variables {
    autoscaling = { min_capacity = 1, max_capacity = 3 }
  }

  expect_failures = [var.autoscaling]
}

run "fargate_rejects_ec2_capacity_providers" {
  command = plan

  variables {
    capacity_provider_strategies = [{ capacity_provider = "test-cluster-capacity-provider" }]
  }

  expect_failures = [var.capacity_provider_strategies]
}

run "ec2_rejects_fargate_only_settings" {
  command = plan

  variables {
    launch_type            = "EC2"
    ephemeral_storage_size = 50
    assign_public_ip       = true
  }

  expect_failures = [var.ephemeral_storage_size, var.assign_public_ip]
}
