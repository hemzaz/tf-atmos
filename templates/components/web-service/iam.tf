# IAM Roles and Policies for Web Service Component

data "aws_partition" "current" {}

data "aws_iam_policy_document" "ecs_tasks_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Task Execution Role (pulls the image, writes logs, resolves secrets)
resource "aws_iam_role" "task_execution" {
  name               = "${local.service_name}-task-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Read access limited to the secrets referenced by the container definition
data "aws_iam_policy_document" "task_execution_secrets" {
  count = length(var.secret_environment_variables) > 0 ? 1 : 0

  dynamic "statement" {
    for_each = length(local.secretsmanager_arns) > 0 ? [local.secretsmanager_arns] : []
    content {
      sid       = "ReadSecretsManagerSecrets"
      actions   = ["secretsmanager:GetSecretValue"]
      resources = statement.value
    }
  }

  dynamic "statement" {
    for_each = length(local.ssm_parameter_arns) > 0 ? [local.ssm_parameter_arns] : []
    content {
      sid       = "ReadSsmParameters"
      actions   = ["ssm:GetParameters"]
      resources = statement.value
    }
  }

  dynamic "statement" {
    for_each = length(var.secrets_kms_key_arns) > 0 ? [var.secrets_kms_key_arns] : []
    content {
      sid       = "DecryptSecrets"
      actions   = ["kms:Decrypt"]
      resources = statement.value

      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values = [
          "secretsmanager.${data.aws_region.current.region}.amazonaws.com",
          "ssm.${data.aws_region.current.region}.amazonaws.com",
        ]
      }
    }
  }
}

locals {
  # valueFrom may carry a JSON key suffix (arn:...:secret:name:key::); grant on the secret ARN
  secretsmanager_arns = distinct([
    for value in values(var.secret_environment_variables) :
    join(":", slice(split(":", value), 0, 7)) if strcontains(value, ":secretsmanager:")
  ])
  ssm_parameter_arns = distinct([
    for value in values(var.secret_environment_variables) : value if strcontains(value, ":ssm:")
  ])
}

resource "aws_iam_role_policy" "task_execution_secrets" {
  count = length(var.secret_environment_variables) > 0 ? 1 : 0

  name   = "${local.service_name}-task-execution-secrets"
  role   = aws_iam_role.task_execution.id
  policy = data.aws_iam_policy_document.task_execution_secrets[0].json
}

# Task Role (application permissions)
resource "aws_iam_role" "task" {
  name               = "${local.service_name}-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json

  tags = local.common_tags
}

# ECS Exec permissions (if enabled)
data "aws_iam_policy_document" "task_exec" {
  statement {
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
    ]
    resources = ["*"] # ssmmessages does not support resource-level permissions
  }
}

resource "aws_iam_role_policy" "task_exec" {
  count = var.enable_execute_command ? 1 : 0

  name   = "${local.service_name}-task-exec"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task_exec.json
}

# Custom task policy (pass an aws_iam_policy_document JSON)
resource "aws_iam_role_policy" "task_custom" {
  count = var.task_role_policy_document != null ? 1 : 0

  name   = "${local.service_name}-task-custom"
  role   = aws_iam_role.task.id
  policy = var.task_role_policy_document
}

# Additional managed policies for the task role
resource "aws_iam_role_policy_attachment" "task_managed_policies" {
  for_each = toset(var.task_role_managed_policy_arns)

  role       = aws_iam_role.task.name
  policy_arn = each.value
}
