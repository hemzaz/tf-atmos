# IAM Roles and Policies for Web Service Component

# Task Execution Role
resource "aws_iam_role" "task_execution" {
  name = "${local.service_name}-task-execution-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
  
  tags = local.common_tags
}

# Attach managed policy for task execution
resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Additional permissions for task execution role
resource "aws_iam_role_policy" "task_execution_additional" {
  count = length(var.secret_environment_variables) > 0 ? 1 : 0
  
  name = "${local.service_name}-task-execution-additional"
  role = aws_iam_role.task_execution.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameters",
          "ssm:GetParameter",
          "secretsmanager:GetSecretValue",
          "kms:Decrypt"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = data.aws_region.current.name
          }
        }
      }
    ]
  })
}

# Task Role (for application permissions)
resource "aws_iam_role" "task" {
  name = "${local.service_name}-task-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
  
  tags = local.common_tags
}

# ECS Exec permissions (if enabled)
resource "aws_iam_role_policy" "task_exec" {
  count = var.enable_execute_command ? 1 : 0
  
  name = "${local.service_name}-task-exec"
  role = aws_iam_role.task.id
  
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

# Custom task policies (for application-specific permissions)
resource "aws_iam_role_policy" "task_custom" {
  count = var.task_role_policy_document != "" ? 1 : 0
  
  name   = "${local.service_name}-task-custom"
  role   = aws_iam_role.task.id
  policy = var.task_role_policy_document
}

# Attach additional managed policies to task role
resource "aws_iam_role_policy_attachment" "task_managed_policies" {
  count = length(var.task_role_managed_policy_arns)
  
  role       = aws_iam_role.task.name
  policy_arn = var.task_role_managed_policy_arns[count.index]
}