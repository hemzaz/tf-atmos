# github-action-token-rotator - keeps a fresh GitHub Actions runner
# registration token in SSM for the github-runners component.
#
# The job of Cloud Posse's aws-github-action-token-rotator, as plain resources:
# its module (cloudposse/github-action-token-rotator/aws 0.1.0) runs
# nodejs16.x, which Lambda no longer creates, from a package in Cloud Posse's
# own public bucket, and passes the App's private key to the function as an
# environment variable, which puts it in the Terraform state. Here the
# function's source is in this component (functions/token-rotator), runs on
# nodejs22.x and reads the key from SSM at run time.
#
# Scanner suppressions are always inline and always carry an honest reason.

locals {
  enabled     = var.enabled
  environment = var.tags["Environment"]
  name        = "${local.environment}-github-token-rotator"
  scope       = var.github_repository_name == null ? var.github_org_name : "${var.github_org_name}/${var.github_repository_name}"

  partition  = one(data.aws_partition.current[*].partition)
  account_id = one(data.aws_caller_identity.current[*].account_id)

  private_key_parameter_arn = local.enabled ? "arn:${local.partition}:ssm:${var.region}:${local.account_id}:parameter${var.parameter_store_private_key_path}" : null
}

data "aws_partition" "current" {
  count = local.enabled ? 1 : 0
}

data "aws_caller_identity" "current" {
  count = local.enabled ? 1 : 0
}

# The token parameter exists before the first rotation, so github-runners and
# its IAM policy can name it. The function owns its value from then on.
resource "aws_ssm_parameter" "token" {
  count = local.enabled ? 1 : 0

  name        = var.parameter_store_token_path
  description = "GitHub Actions runner registration token for ${local.scope}, rotated by ${local.name}"
  type        = "SecureString"
  key_id      = var.kms_key_arn
  value       = "rotated-by-${local.name}"

  lifecycle {
    ignore_changes = [value]
  }
}

data "archive_file" "function" {
  count = local.enabled ? 1 : 0

  type        = "zip"
  source_dir  = "${path.module}/functions/token-rotator"
  excludes    = ["index.test.mjs"]
  output_path = "${path.module}/.archives/token-rotator.zip"
  # Pinned so the hash depends only on file content (see the lambda component).
  output_file_mode = "0644"
}

data "aws_iam_policy_document" "assume" {
  count = local.enabled ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "function" {
  count = local.enabled ? 1 : 0

  name               = local.name
  assume_role_policy = data.aws_iam_policy_document.assume[0].json
}

data "aws_iam_policy_document" "function" {
  count = local.enabled ? 1 : 0

  statement {
    sid       = "ReadPrivateKey"
    actions   = ["ssm:GetParameter"]
    resources = [local.private_key_parameter_arn]
  }

  statement {
    sid       = "WriteToken"
    actions   = ["ssm:PutParameter"]
    resources = [aws_ssm_parameter.token[0].arn]
  }

  # Decrypt the private key and encrypt the token, through SSM only.
  statement {
    sid       = "ParameterKey"
    actions   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey"]
    resources = [var.kms_key_arn]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.${var.region}.amazonaws.com"]
    }
  }

  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.function[0].arn}:*"]
  }
}

resource "aws_iam_role_policy" "function" {
  count = local.enabled ? 1 : 0

  name   = local.name
  role   = aws_iam_role.function[0].id
  policy = data.aws_iam_policy_document.function[0].json
}

resource "aws_cloudwatch_log_group" "function" {
  #checkov:skip=CKV_AWS_338:Retention is an input (log_retention_days) and a per-stack cost decision, as on the repo's other log groups
  count = local.enabled ? 1 : 0

  name              = "/aws/lambda/${local.name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn
}

resource "aws_lambda_function" "function" {
  #checkov:skip=CKV_AWS_117:Calls the GitHub API and SSM only; outside a VPC it needs no NAT path or endpoints, as in Cloud Posse's module
  #checkov:skip=CKV_AWS_116:Scheduled; a failed run is retried by the next one (the token is valid for an hour, the schedule runs every 30 minutes), so a dead-letter queue would hold nothing to act on
  #checkov:skip=CKV_AWS_272:The package is built from this component's own source by archive_file; no signing profile, as in Cloud Posse's module
  #checkov:skip=CKV_AWS_50:One short scheduled call; X-Ray would bill per trace for nothing to trace
  count = local.enabled ? 1 : 0

  function_name                  = local.name
  description                    = "Rotates the GitHub Actions runner registration token for ${local.scope}"
  role                           = aws_iam_role.function[0].arn
  runtime                        = "nodejs22.x"
  handler                        = "index.handler"
  filename                       = data.archive_file.function[0].output_path
  source_code_hash               = data.archive_file.function[0].output_base64sha256
  memory_size                    = var.memory_size
  timeout                        = 30
  reserved_concurrent_executions = 1
  kms_key_arn                    = var.kms_key_arn

  # No secret here: the key and the token stay in SSM.
  environment {
    variables = {
      GITHUB_APP_ID          = var.github_app_id
      GITHUB_INSTALLATION_ID = var.github_app_installation_id
      GITHUB_SCOPE           = local.scope
      PRIVATE_KEY_PARAMETER  = var.parameter_store_private_key_path
      TOKEN_PARAMETER        = aws_ssm_parameter.token[0].name
      TOKEN_KMS_KEY_ID       = var.kms_key_arn
    }
  }

  depends_on = [aws_cloudwatch_log_group.function, aws_iam_role_policy.function]
}

resource "aws_cloudwatch_event_rule" "schedule" {
  count = local.enabled ? 1 : 0

  name                = local.name
  description         = "Rotate the GitHub Actions runner registration token"
  schedule_expression = var.schedule_expression
}

resource "aws_cloudwatch_event_target" "schedule" {
  count = local.enabled ? 1 : 0

  rule = aws_cloudwatch_event_rule.schedule[0].name
  arn  = aws_lambda_function.function[0].arn
}

resource "aws_lambda_permission" "schedule" {
  count = local.enabled ? 1 : 0

  statement_id  = "AllowScheduledRotation"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.function[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.schedule[0].arn
}
