# Offline tests: the real AWS provider with dummy credentials, as in
# sqs/tests. aws_iam_policy_document is computed locally, so the delivery
# policy can be asserted. Every check that would call AWS is skipped, and
# without subnet_ids the S3 prefix-list lookup is not made, so nothing reaches
# AWS (all runs are plans). data.aws_caller_identity.current is only fetched
# when secretsmanager_source_arn is set (see main.tf), so override_data below
# only matters for that one run -- as in cost-optimization/tests.
# Run: terraform init -backend=false && terraform test

provider "aws" {
  region                      = "eu-west-2"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
}

override_data {
  target = data.aws_caller_identity.current
  values = {
    account_id = "123456789012"
  }
}

variables {
  region        = "eu-west-2"
  function_name = "welcome-email"
  handler       = "index.handler"
  s3_bucket     = "test-artifacts"
  s3_key        = "welcome-email/1.0.0.zip"
  tags = {
    Environment = "test"
    ManagedBy   = "Terraform"
  }
}

run "no_destinations_no_delivery_policy" {
  command = plan

  assert {
    condition     = length(aws_iam_role_policy.delivery) == 0
    error_message = "Without an SQS/SNS destination the role gets no delivery policy."
  }
}

run "failure_queue_gets_send_and_key_access" {
  command = plan

  variables {
    configure_event_invoke = true
    on_failure_destination = "arn:aws:sqs:eu-west-2:123456789012:test-welcome-email-failures"
    delivery_kms_key_arn   = "arn:aws:kms:eu-west-2:123456789012:key/00000000-0000-0000-0000-000000000000"
  }

  assert {
    condition     = aws_lambda_function_event_invoke_config.main[0].destination_config[0].on_failure[0].destination == "arn:aws:sqs:eu-west-2:123456789012:test-welcome-email-failures"
    error_message = "on_failure_destination is the event invoke config's on_failure destination."
  }

  assert {
    condition     = aws_iam_role_policy.delivery[0].name == "test-welcome-email-delivery"
    error_message = "The delivery policy is <Environment>-<function_name>-delivery."
  }

  assert {
    condition = (
      one([for s in jsondecode(data.aws_iam_policy_document.delivery[0].json).Statement : s if s.Sid == "SendToDeliveryQueues"]).Action == "sqs:SendMessage"
      && one([for s in jsondecode(data.aws_iam_policy_document.delivery[0].json).Statement : s if s.Sid == "SendToDeliveryQueues"]).Resource == "arn:aws:sqs:eu-west-2:123456789012:test-welcome-email-failures"
    )
    error_message = "The role may send to the failure queue, and only to it."
  }

  assert {
    condition     = toset(one([for s in jsondecode(data.aws_iam_policy_document.delivery[0].json).Statement : s if s.Sid == "UseDeliveryKey"]).Action) == toset(["kms:GenerateDataKey", "kms:Decrypt"])
    error_message = "The role may use the queue's key to encrypt messages."
  }

  assert {
    condition     = length([for s in jsondecode(data.aws_iam_policy_document.delivery[0].json).Statement : s if s.Sid == "PublishToDeliveryTopics"]) == 0
    error_message = "No SNS statement without an SNS destination."
  }
}

run "rejects_a_non_kms_delivery_key" {
  command = plan

  variables {
    delivery_kms_key_arn = "alias/aws/sqs"
  }

  expect_failures = [var.delivery_kms_key_arn]
}

run "no_secretsmanager_source_arn_no_permission" {
  command = plan

  assert {
    condition     = length(aws_lambda_permission.secretsmanager) == 0
    error_message = "Without secretsmanager_source_arn the function gets no Secrets Manager invoke permission."
  }
}

run "secretsmanager_source_arn_gets_scoped_invoke_permission" {
  command = plan

  variables {
    secretsmanager_source_arn = "arn:aws:secretsmanager:eu-west-2:123456789012:secret:microservices/dev/auth/jwt-signing-AbCdEf"
  }

  assert {
    condition     = aws_lambda_permission.secretsmanager[0].principal == "secretsmanager.amazonaws.com"
    error_message = "The permission's principal is secretsmanager.amazonaws.com."
  }

  assert {
    condition     = aws_lambda_permission.secretsmanager[0].source_arn == "arn:aws:secretsmanager:eu-west-2:123456789012:secret:microservices/dev/auth/jwt-signing-AbCdEf"
    error_message = "source_arn is scoped to the one secret."
  }

  assert {
    condition     = aws_lambda_permission.secretsmanager[0].source_account == "123456789012"
    error_message = "source_account is scoped to this account."
  }
}

run "rejects_a_non_secretsmanager_source_arn" {
  command = plan

  variables {
    secretsmanager_source_arn = "arn:aws:sqs:eu-west-2:123456789012:some-queue"
  }

  expect_failures = [var.secretsmanager_source_arn]
}

run "source_dir_packages_the_function_itself" {
  command = plan

  variables {
    function_name = "jwt-secret-rotation"
    handler       = "lambda_function.lambda_handler"
    runtime       = "python3.13"
    s3_bucket     = null
    s3_key        = null
    source_dir    = "functions/jwt-secret-rotation"
  }

  assert {
    condition     = aws_lambda_function.main.filename == "${path.module}/.archives/jwt-secret-rotation.zip"
    error_message = "source_dir is zipped to .archives/<function_name>.zip under this component."
  }

  assert {
    condition     = aws_lambda_function.main.source_code_hash != null
    error_message = "archive_file's own hash drives source_code_hash when source_dir is set."
  }
}

run "rejects_two_packaging_sources_at_once" {
  command = plan

  variables {
    function_name = "jwt-secret-rotation"
    handler       = "lambda_function.lambda_handler"
    runtime       = "python3.13"
    source_dir    = "functions/jwt-secret-rotation"
    # s3_bucket/s3_key are already set by the file-level variables block above,
    # so this run now has both source_dir and s3_bucket -- exactly the
    # violation the precondition on aws_lambda_function.main rejects.
  }

  expect_failures = [aws_lambda_function.main]
}
