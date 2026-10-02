# Container job definitions, their log group and their roles. Roles follow the
# Cloud Posse ecs-service pattern: created by the component unless an ARN is
# given (execution_role_arn per instance, job_role_arn per definition).
#
# - Execution role (ECS/Fargate agent: image pull, awslogs, secrets): one
#   shared <Environment>-<name>-job-execution, created when a FARGATE
#   definition or a definition with secrets exists. EC2 definitions without
#   secrets need none: the instance role pulls and logs for them.
# - Job role (the job's own AWS access): per definition, created as
#   <Environment>-<name>-<key>-job when it has job_role_policy_arns or
#   job_role_policy_json.
#
# Both trust ecs-tasks.amazonaws.com limited to this account's ECS tasks in
# this region (aws:SourceAccount + aws:SourceArn arn:aws:ecs:<region>:<acct>:*),
# the trust policy AWS documents for task roles against the confused deputy
# (a cluster-specific SourceArn is not supported, hence the wildcard).

locals {
  job_definitions = {
    for k, d in var.job_definitions : k => merge(d, {
      name    = "${local.prefix}-${k}"
      fargate = d.platform_capability == "FARGATE"
    }) if local.enabled
  }

  job_fargate_present   = anytrue([for d in values(local.job_definitions) : d.fargate])
  job_log_group_enabled = length(local.job_definitions) > 0
  job_log_group_name    = "/aws/batch/${local.prefix}"

  # Definitions whose agent needs the execution role.
  execution_role_keys    = [for k, d in local.job_definitions : k if d.fargate || length(d.secrets) > 0]
  execution_role_enabled = var.execution_role_arn == null && length(local.execution_role_keys) > 0
  execution_role_name    = "${local.prefix}-job-execution"
  execution_role_arn     = var.execution_role_arn != null ? var.execution_role_arn : one(aws_iam_role.job_execution[*].arn)

  # Secrets Manager: the IAM resource is the secret ARN itself (the first 7
  # ':' fields), without the valueFrom's optional json-key/version tail.
  secret_value_froms = distinct(flatten([for d in values(local.job_definitions) : values(d.secrets)]))
  secretsmanager_arns = distinct([
    for a in local.secret_value_froms : join(":", slice(split(":", a), 0, 7)) if split(":", a)[2] == "secretsmanager"
  ])
  ssm_parameter_arns = distinct([for a in local.secret_value_froms : a if split(":", a)[2] == "ssm"])

  job_roles = {
    for k, d in local.job_definitions : k => merge(d, { role_name = "${d.name}-job" })
    if d.job_role_arn == null && (length(d.job_role_policy_arns) > 0 || d.job_role_policy_json != null)
  }
  job_role_policy_attachments = merge([
    for k, d in local.job_roles : { for a in d.job_role_policy_arns : "${k}:${a}" => { key = k, policy_arn = a } }
  ]...)

  ecs_tasks_assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
        ArnLike      = { "aws:SourceArn" = "arn:${data.aws_partition.current.partition}:ecs:${var.region}:${data.aws_caller_identity.current.account_id}:*" }
      }
    }]
  })
}

data "aws_caller_identity" "current" {}

resource "aws_cloudwatch_log_group" "jobs" {
  # checkov:skip=CKV_AWS_338:Retention mirrors the repo's other log groups (log_retention_days, default 90) and is a per-stack cost decision, not a module one.
  count = local.job_log_group_enabled ? 1 : 0

  name              = local.job_log_group_name
  kms_key_id        = var.log_kms_key_arn
  retention_in_days = var.log_retention_days

  tags = { Name = local.job_log_group_name }
}

resource "aws_iam_role" "job_execution" {
  count = local.execution_role_enabled ? 1 : 0

  name               = local.execution_role_name
  assume_role_policy = local.ecs_tasks_assume_role_policy

  tags = { Name = local.execution_role_name }

  lifecycle {
    precondition {
      condition     = length(local.execution_role_name) <= 64
      error_message = "The execution role name (<Environment>-<name>-job-execution, \"${local.execution_role_name}\") must be 64 characters or fewer."
    }
  }
}

# The AmazonECSTaskExecutionRolePolicy permissions, scoped: ECR pull (FARGATE
# only; GetAuthorizationToken has no resource scope), awslogs to this
# component's log group, and exactly the definitions' secrets.
resource "aws_iam_role_policy" "job_execution" {
  count = local.execution_role_enabled ? 1 : 0

  name = "job-execution"
  role = aws_iam_role.job_execution[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      local.job_fargate_present ? [{
        Sid      = "ECRAuthorization"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      }] : [],
      local.job_fargate_present ? [{
        Sid      = "ECRPull"
        Effect   = "Allow"
        Action   = ["ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage"]
        Resource = length(var.ecr_repository_arns) > 0 ? var.ecr_repository_arns : ["*"]
      }] : [],
      [{
        Sid      = "Logs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.jobs[0].arn}:log-stream:*"
      }],
      length(local.secretsmanager_arns) == 0 ? [] : [{
        Sid      = "SecretsManager"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = local.secretsmanager_arns
      }],
      length(local.ssm_parameter_arns) == 0 ? [] : [{
        Sid      = "SSMParameters"
        Effect   = "Allow"
        Action   = ["ssm:GetParameters"]
        Resource = local.ssm_parameter_arns
      }],
      var.secrets_kms_key_arn == null || length(local.secret_value_froms) == 0 ? [] : [{
        Sid      = "SecretsKMS"
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = var.secrets_kms_key_arn
        Condition = {
          StringEquals = { "kms:ViaService" = ["secretsmanager.${var.region}.amazonaws.com", "ssm.${var.region}.amazonaws.com"] }
        }
      }],
    )
  })
}

resource "aws_iam_role" "job" {
  for_each = local.job_roles

  name               = each.value.role_name
  assume_role_policy = local.ecs_tasks_assume_role_policy

  tags = { Name = each.value.role_name }

  lifecycle {
    precondition {
      condition     = length(each.value.role_name) <= 64
      error_message = "The job role name (<Environment>-<name>-<key>-job, \"${each.value.role_name}\") must be 64 characters or fewer."
    }
  }
}

resource "aws_iam_role_policy_attachment" "job" {
  for_each = local.job_role_policy_attachments

  role       = aws_iam_role.job[each.value.key].name
  policy_arn = each.value.policy_arn
}

resource "aws_iam_role_policy" "job" {
  for_each = { for k, d in local.job_roles : k => d if d.job_role_policy_json != null }

  name   = "job"
  role   = aws_iam_role.job[each.key].id
  policy = each.value.job_role_policy_json
}

locals {
  # Batch container_properties (RegisterJobDefinition's camelCase shape),
  # with unset attributes dropped so the registered JSON matches what Batch
  # returns and plans stay clean.
  job_container_properties = {
    for k, d in local.job_definitions : k => {
      for name, value in {
        image   = d.image
        command = length(d.command) > 0 ? d.command : null
        resourceRequirements = concat(
          [{ type = "VCPU", value = tostring(d.vcpu) }, { type = "MEMORY", value = tostring(d.memory) }],
          d.gpu == null ? [] : [{ type = "GPU", value = tostring(d.gpu) }],
        )
        environment      = length(d.environment) > 0 ? [for n, v in d.environment : { name = n, value = v }] : null
        secrets          = length(d.secrets) > 0 ? [for n, v in d.secrets : { name = n, valueFrom = v }] : null
        jobRoleArn       = d.job_role_arn != null ? d.job_role_arn : try(aws_iam_role.job[k].arn, null)
        executionRoleArn = contains(local.execution_role_keys, k) ? local.execution_role_arn : null

        readonlyRootFilesystem = d.readonly_root_filesystem
        privileged             = d.fargate ? null : d.privileged
        user                   = d.user
        ulimits                = length(d.ulimits) > 0 ? [for u in d.ulimits : { name = u.name, softLimit = u.soft_limit, hardLimit = u.hard_limit }] : null
        linuxParameters = d.linux_parameters == null ? null : {
          for lk, lv in {
            initProcessEnabled = d.linux_parameters.init_process_enabled
            sharedMemorySize   = d.linux_parameters.shared_memory_size
            devices = length(d.linux_parameters.devices) == 0 ? null : [
              for dev in d.linux_parameters.devices : {
                for dk, dv in { hostPath = dev.host_path, containerPath = dev.container_path, permissions = dev.permissions } : dk => dv if dv != null
              }
            ]
          } : lk => lv if lv != null
        }

        logConfiguration = {
          logDriver = "awslogs"
          options = {
            "awslogs-group"         = local.job_log_group_name
            "awslogs-region"        = var.region
            "awslogs-stream-prefix" = coalesce(d.log_stream_prefix, k)
          }
        }

        networkConfiguration         = d.fargate ? { assignPublicIp = coalesce(d.assign_public_ip, "DISABLED") } : null
        fargatePlatformConfiguration = d.fargate ? { platformVersion = coalesce(d.fargate_platform_version, "LATEST") } : null
        ephemeralStorage             = d.ephemeral_storage_gib == null ? null : { sizeInGiB = d.ephemeral_storage_gib }
        runtimePlatform              = d.cpu_architecture == null ? null : { cpuArchitecture = d.cpu_architecture, operatingSystemFamily = "LINUX" }
      } : name => value if value != null
    }
  }
}

resource "aws_batch_job_definition" "this" {
  for_each = local.job_definitions

  name                  = each.value.name
  type                  = "container"
  platform_capabilities = [each.value.platform_capability]
  container_properties  = jsonencode(local.job_container_properties[each.key])
  parameters            = length(each.value.parameters) > 0 ? each.value.parameters : null
  propagate_tags        = each.value.propagate_tags
  scheduling_priority   = each.value.scheduling_priority

  retry_strategy {
    attempts = each.value.retry_strategy.attempts

    dynamic "evaluate_on_exit" {
      for_each = each.value.retry_strategy.evaluate_on_exit
      content {
        action           = evaluate_on_exit.value.action
        on_exit_code     = evaluate_on_exit.value.on_exit_code
        on_reason        = evaluate_on_exit.value.on_reason
        on_status_reason = evaluate_on_exit.value.on_status_reason
      }
    }
  }

  dynamic "timeout" {
    for_each = each.value.timeout_seconds == null ? [] : [each.value.timeout_seconds]
    content {
      attempt_duration_seconds = timeout.value
    }
  }

  tags = merge(each.value.tags, { Name = each.value.name })

  # A job must not start before its roles can do their work.
  depends_on = [
    aws_iam_role_policy.job_execution,
    aws_iam_role_policy.job,
    aws_iam_role_policy_attachment.job,
  ]

  lifecycle {
    precondition {
      condition     = length(each.value.name) <= 128
      error_message = "The job definition name (<Environment>-<name>-<key>, \"${each.value.name}\") must be 128 characters or fewer."
    }
  }
}
