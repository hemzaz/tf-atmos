##############################################
# Secrets Manager Secret
##############################################

resource "aws_secretsmanager_secret" "main" {
  name                    = "${var.name_prefix}-secret"
  description             = var.description
  kms_key_id              = var.kms_key_id
  recovery_window_in_days = var.recovery_window_days

  dynamic "replica" {
    for_each = var.replica_regions
    content {
      region     = replica.value
      kms_key_id = var.kms_key_id
    }
  }

  tags = merge(
    var.tags,
    {
      Name       = "${var.name_prefix}-secret"
      Module     = "secrets-manager-advanced"
      ManagedBy  = "terraform"
    }
  )
}

##############################################
# Secret Version
##############################################

resource "aws_secretsmanager_secret_version" "main" {
  count = var.secret_string != null || var.secret_binary != null ? 1 : 0

  secret_id     = aws_secretsmanager_secret.main.id
  secret_string = var.secret_string
  secret_binary = var.secret_binary != null ? base64decode(var.secret_binary) : null
}

##############################################
# Rotation Configuration
##############################################

resource "aws_secretsmanager_secret_rotation" "main" {
  count = var.enable_rotation ? 1 : 0

  secret_id           = aws_secretsmanager_secret.main.id
  rotation_lambda_arn = var.create_rotation_lambda ? aws_lambda_function.rotation[0].arn : var.rotation_lambda_arn

  rotation_rules {
    automatically_after_days = var.rotation_days
  }

  depends_on = [
    aws_lambda_permission.rotation
  ]
}

##############################################
# Rotation Lambda Function
##############################################

resource "aws_lambda_function" "rotation" {
  count = var.create_rotation_lambda ? 1 : 0

  filename      = "${path.module}/templates/rotation_lambda.zip"
  function_name = "${var.name_prefix}-rotation"
  role          = aws_iam_role.rotation[0].arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.11"
  timeout       = 30

  environment {
    variables = {
      SECRETS_MANAGER_ENDPOINT = "https://secretsmanager.${data.aws_region.current.name}.amazonaws.com"
    }
  }

  tags = merge(
    var.tags,
    {
      Name      = "${var.name_prefix}-rotation"
      ManagedBy = "terraform"
    }
  )
}

resource "aws_lambda_permission" "rotation" {
  count = var.create_rotation_lambda ? 1 : 0

  statement_id  = "AllowSecretsManager"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.rotation[0].function_name
  principal     = "secretsmanager.amazonaws.com"
}

##############################################
# IAM Role for Lambda Rotation
##############################################

resource "aws_iam_role" "rotation" {
  count = var.create_rotation_lambda ? 1 : 0

  name = "${var.name_prefix}-rotation-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "rotation" {
  count = var.create_rotation_lambda ? 1 : 0

  name = "${var.name_prefix}-rotation-policy"
  role = aws_iam_role.rotation[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:DescribeSecret",
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue",
          "secretsmanager:UpdateSecretVersionStage"
        ]
        Resource = aws_secretsmanager_secret.main.arn
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetRandomPassword"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
