# The task execution role and the task role, Cloud Posse ecs-alb-service-task
# pattern: created by the component unless an ARN is given (task_exec_role_arn,
# task_role_arn). Same shape as the batch component's job roles.
#
# - Execution role (the ECS agent: image pull, awslogs, secrets): always used,
#   <Environment>-<name>-task-execution unless task_exec_role_arn is given.
# - Task role (the containers' own AWS access): <Environment>-<name>-task,
#   created when task_policy_arns, task_policy_json or exec_enabled is set,
#   unless task_role_arn is given. Without either the tasks have no AWS
#   credentials.
#
# Both trust ecs-tasks.amazonaws.com. The task role uses the trust AWS
# documents for task roles against the confused deputy: aws:SourceAccount plus
# aws:SourceArn arn:aws:ecs:<region>:<acct>:* (a cluster-specific SourceArn is
# not supported, hence the wildcard). The execution role gets aws:SourceAccount
# only: the ECS task execution role docs show no SourceArn, and one the agent
# does not send would fail every task at start.

locals {
  task_exec_role_enabled = local.enabled && var.task_exec_role_arn == null
  task_exec_role_name    = "${local.prefix}-task-execution"
  task_exec_role_arn     = var.task_exec_role_arn != null ? var.task_exec_role_arn : one(aws_iam_role.task_execution[*].arn)

  task_role_enabled = local.enabled && var.task_role_arn == null && (
    length(var.task_policy_arns) > 0 || var.task_policy_json != null || var.exec_enabled
  )
  task_role_name = "${local.prefix}-task"
  task_role_arn  = var.task_role_arn != null ? var.task_role_arn : one(aws_iam_role.task[*].arn)

  # Secrets Manager: the IAM resource is the secret ARN itself (the first 7
  # ':' fields), without the valueFrom's optional json-key/version tail.
  secret_value_froms = distinct(flatten([for c in values(var.containers) : values(c.secrets)]))
  secretsmanager_arns = distinct([
    for a in local.secret_value_froms : join(":", slice(split(":", a), 0, 7)) if split(":", a)[2] == "secretsmanager"
  ])
  ssm_parameter_arns = distinct([for a in local.secret_value_froms : a if split(":", a)[2] == "ssm"])

  task_role_assume_role_policy = jsonencode({
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

  task_exec_role_assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
      }
    }]
  })
}

data "aws_partition" "current" {}

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "task_execution" {
  count = local.task_exec_role_enabled ? 1 : 0

  name               = local.task_exec_role_name
  assume_role_policy = local.task_exec_role_assume_role_policy

  tags = { Name = local.task_exec_role_name }

  lifecycle {
    precondition {
      condition     = length(local.task_exec_role_name) <= 64
      error_message = "The execution role name (<Environment>-<name>-task-execution, \"${local.task_exec_role_name}\") must be 64 characters or fewer."
    }
  }
}

# The AmazonECSTaskExecutionRolePolicy permissions, scoped: ECR pull
# (GetAuthorizationToken has no resource scope), awslogs to this component's
# log group, and exactly the containers' secrets.
resource "aws_iam_role_policy" "task_execution" {
  count = local.task_exec_role_enabled ? 1 : 0

  name = "task-execution"
  role = aws_iam_role.task_execution[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [{
        Sid      = "ECRAuthorization"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
        }, {
        Sid      = "ECRPull"
        Effect   = "Allow"
        Action   = ["ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage"]
        Resource = length(var.ecr_repository_arns) > 0 ? var.ecr_repository_arns : ["*"]
        }, {
        Sid      = "Logs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.this[0].arn}:log-stream:*"
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

resource "aws_iam_role" "task" {
  count = local.task_role_enabled ? 1 : 0

  name               = local.task_role_name
  assume_role_policy = local.task_role_assume_role_policy

  tags = { Name = local.task_role_name }

  lifecycle {
    precondition {
      condition     = length(local.task_role_name) <= 64
      error_message = "The task role name (<Environment>-<name>-task, \"${local.task_role_name}\") must be 64 characters or fewer."
    }
  }
}

resource "aws_iam_role_policy_attachment" "task" {
  for_each = local.task_role_enabled ? toset(var.task_policy_arns) : toset([])

  role       = aws_iam_role.task[0].name
  policy_arn = each.value
}

resource "aws_iam_role_policy" "task" {
  count = local.task_role_enabled && var.task_policy_json != null ? 1 : 0

  name   = "task"
  role   = aws_iam_role.task[0].id
  policy = var.task_policy_json
}

# ECS Exec: the SSM agent in the task opens its session channels with the task
# role (ssmmessages has no resource scope), and decrypts with the cluster's
# exec key when it sets one.
resource "aws_iam_role_policy" "task_exec" {
  count = local.task_role_enabled && var.exec_enabled ? 1 : 0

  name = "ecs-exec"
  role = aws_iam_role.task[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [{
        Sid      = "SSMMessages"
        Effect   = "Allow"
        Action   = ["ssmmessages:CreateControlChannel", "ssmmessages:CreateDataChannel", "ssmmessages:OpenControlChannel", "ssmmessages:OpenDataChannel"]
        Resource = "*"
      }],
      var.exec_kms_key_arn == null ? [] : [{
        Sid      = "ExecKMS"
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = var.exec_kms_key_arn
      }],
    )
  })
}
