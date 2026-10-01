# Offline tests: the real AWS provider with dummy credentials, as in
# sqs/tests. aws_iam_policy_document is computed locally, so the delivery
# policy can be asserted. Every check that would call AWS is skipped, and
# without subnet_ids the S3 prefix-list lookup is not made, so nothing reaches
# AWS (all runs are plans). data.aws_caller_identity.current is only fetched
# when secretsmanager_source_arn is set (see main.tf), so override_data below
# only matters for that one run -- as in cost-optimization/tests.
# Run: terraform init -backend=false && terraform test

provider "aws" {
  region                      = "us-east-1"
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
  region        = "us-east-1"
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
    on_failure_destination = "arn:aws:sqs:us-east-1:123456789012:test-welcome-email-failures"
    delivery_kms_key_arn   = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000"
  }

  assert {
    condition     = aws_lambda_function_event_invoke_config.main[0].destination_config[0].on_failure[0].destination == "arn:aws:sqs:us-east-1:123456789012:test-welcome-email-failures"
    error_message = "on_failure_destination is the event invoke config's on_failure destination."
  }

  assert {
    condition     = aws_iam_role_policy.delivery[0].name == "test-welcome-email-delivery"
    error_message = "The delivery policy is <Environment>-<function_name>-delivery."
  }

  assert {
    condition = (
      one([for s in jsondecode(data.aws_iam_policy_document.delivery[0].json).Statement : s if s.Sid == "SendToDeliveryQueues"]).Action == "sqs:SendMessage"
      && one([for s in jsondecode(data.aws_iam_policy_document.delivery[0].json).Statement : s if s.Sid == "SendToDeliveryQueues"]).Resource == "arn:aws:sqs:us-east-1:123456789012:test-welcome-email-failures"
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

# S4: S3 bucket ARNs carry no account and bucket names are global, so the S3
# invoke permission must pin the bucket owner with source_account.
run "s3_invoke_permission_pins_the_source_account" {
  command = plan

  variables {
    s3_source_arn = "arn:aws:s3:::test-uploads"
  }

  assert {
    condition = (
      aws_lambda_permission.s3[0].principal == "s3.amazonaws.com"
      && aws_lambda_permission.s3[0].source_arn == "arn:aws:s3:::test-uploads"
      && aws_lambda_permission.s3[0].source_account == "123456789012"
    )
    error_message = "The S3 invoke permission must name the bucket (source_arn) and this account (source_account)."
  }
}

run "s3_source_arn_rejects_a_wildcard" {
  command = plan

  variables {
    s3_source_arn = "arn:aws:s3:::*"
  }

  expect_failures = [var.s3_source_arn]
}

run "secretsmanager_source_arn_gets_scoped_invoke_permission" {
  command = plan

  variables {
    secretsmanager_source_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:microservices/dev/auth/jwt-signing-AbCdEf"
  }

  assert {
    condition     = aws_lambda_permission.secretsmanager[0].principal == "secretsmanager.amazonaws.com"
    error_message = "The permission's principal is secretsmanager.amazonaws.com."
  }

  assert {
    condition     = aws_lambda_permission.secretsmanager[0].source_arn == "arn:aws:secretsmanager:us-east-1:123456789012:secret:microservices/dev/auth/jwt-signing-AbCdEf"
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
    secretsmanager_source_arn = "arn:aws:sqs:us-east-1:123456789012:some-queue"
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

run "no_kms_key_arn_no_env_decrypt_grant" {
  command = plan

  assert {
    condition     = length(aws_iam_role_policy.lambda_kms_env) == 0
    error_message = "Without kms_key_arn the execution role gets no environment variable decrypt grant."
  }
}

run "kms_key_arn_gets_a_scoped_env_decrypt_grant" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000"
  }

  assert {
    condition     = length(aws_iam_role_policy.lambda_kms_env) == 1
    error_message = "kms_key_arn gets the execution role a kms:Decrypt grant for environment variable decryption."
  }

  assert {
    condition = (
      one([for s in jsondecode(aws_iam_role_policy.lambda_kms_env[0].policy).Statement : s if s.Sid == "AllowEnvironmentVariableDecryption"]).Resource
      == "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000"
    )
    error_message = "The grant is scoped to kms_key_arn."
  }

  assert {
    condition = (
      one([for s in jsondecode(aws_iam_role_policy.lambda_kms_env[0].policy).Statement : s if s.Sid == "AllowEnvironmentVariableDecryption"]).Condition.StringEquals["kms:EncryptionContext:aws:lambda:FunctionArn"]
      == "arn:aws:lambda:us-east-1:123456789012:function:test-welcome-email"
    )
    error_message = "The grant is further scoped by the encryption context Lambda itself sets: this function's own (deterministic) ARN."
  }
}

run "no_rotation_secret_arn_no_rotation_resource" {
  command = plan

  assert {
    condition     = length(aws_secretsmanager_secret_rotation.this) == 0
    error_message = "Without rotation_secret_arn this function does not configure rotation on any secret."
  }
}

run "rotation_secret_arn_configures_rotation_from_this_instance" {
  command = plan

  # custom_policy, kms_key_arn and subnet_ids each give this rotation
  # resource's depends_on a real (count = 1) resource to resolve --
  # aws_iam_role_policy.lambda_custom, aws_iam_role_policy.lambda_kms_env and
  # aws_iam_role_policy_attachment.lambda_vpc_access respectively (lambda_basic
  # is unconditional). If depends_on ever regresses to referencing a resource
  # address that does not exist for this configuration, `terraform plan`
  # fails outright with "Reference to undeclared resource" -- this run is the
  # regression guard for that, not just for the rotation resource's own
  # attributes below. See main.tf's own comment on aws_secretsmanager_secret_rotation.this
  # for why depends_on needs all four: aws_lambda_function.main only has an
  # IMPLICIT dependency on aws_iam_role.lambda (via its arn), never on the
  # role's own policies, so without these, Secrets Manager could invoke this
  # function before its permissions exist or have propagated.
  variables {
    secretsmanager_source_arn    = "arn:aws:secretsmanager:us-east-1:123456789012:secret:microservices/dev/cache/auth-token-AbCdEf"
    rotation_secret_arn          = "arn:aws:secretsmanager:us-east-1:123456789012:secret:microservices/dev/cache/auth-token-AbCdEf"
    rotation_days                = 30
    custom_policy                = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = "secretsmanager:GetSecretValue", Resource = "*" }] })
    kms_key_arn                  = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000"
    vpc_id                       = "vpc-0123456789abcdef0"
    subnet_ids                   = ["subnet-0123456789abcdef0"]
    vpc_endpoint_prefix_list_ids = ["pl-0123456789abcdef0"]
  }

  assert {
    condition     = length(aws_iam_role_policy.lambda_custom) == 1 && length(aws_iam_role_policy.lambda_kms_env) == 1 && length(aws_iam_role_policy_attachment.lambda_vpc_access) == 1
    error_message = "This run must actually instantiate every resource aws_secretsmanager_secret_rotation.this depends_on, or it is not exercising the ordering fix."
  }

  assert {
    condition     = aws_secretsmanager_secret_rotation.this[0].secret_id == "arn:aws:secretsmanager:us-east-1:123456789012:secret:microservices/dev/cache/auth-token-AbCdEf"
    error_message = "rotation_secret_arn becomes the rotation resource's secret_id."
  }

  assert {
    condition     = aws_secretsmanager_secret_rotation.this[0].rotation_lambda_arn == "arn:aws:lambda:us-east-1:123456789012:function:test-welcome-email"
    error_message = "rotation_lambda_arn is this function's own (deterministic) ARN."
  }

  assert {
    condition     = aws_secretsmanager_secret_rotation.this[0].rotation_rules[0].automatically_after_days == 30
    error_message = "rotation_days becomes automatically_after_days."
  }

  assert {
    condition     = aws_secretsmanager_secret_rotation.this[0].rotate_immediately == false
    error_message = "rotate_immediately defaults to false."
  }
}

run "rotation_secret_arn_requires_secretsmanager_source_arn" {
  command = plan

  variables {
    rotation_secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:microservices/dev/cache/auth-token-AbCdEf"
  }

  expect_failures = [aws_secretsmanager_secret_rotation.this]
}

run "rotation_secret_arn_requires_matching_secretsmanager_source_arn" {
  command = plan

  # secretsmanager_source_arn set, but to a DIFFERENT secret than
  # rotation_secret_arn -- the precondition must reject this too, not just
  # a null secretsmanager_source_arn, since a mismatch would otherwise plan
  # cleanly and only fail later at RotateSecret (the invoke permission's
  # SourceArn would name a different secret than the one rotation is
  # configured on).
  variables {
    secretsmanager_source_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:microservices/dev/api/other-secret-AbCdEf"
    rotation_secret_arn       = "arn:aws:secretsmanager:us-east-1:123456789012:secret:microservices/dev/cache/auth-token-AbCdEf"
  }

  expect_failures = [aws_secretsmanager_secret_rotation.this]
}

run "additional_security_group_ids_are_attached_alongside_the_own_sg" {
  command = plan

  # aws_security_group.lambda[0].id is Computed (unknown at plan for a real,
  # non-mocked provider), which otherwise makes the whole security_group_ids
  # SET unknown (set cardinality depends on element equality, so even
  # length() cannot be known with an unknown element in it) -- override it to
  # a known value so vpc_config's security_group_ids is assertable below.
  override_resource {
    target          = aws_security_group.lambda[0]
    override_during = plan
    values = {
      id = "sg-lambdaown00000000"
    }
  }

  variables {
    vpc_id     = "vpc-0123456789abcdef0"
    subnet_ids = ["subnet-0123456789abcdef0"]
    # Set to avoid the real AWS lookup data.aws_ec2_managed_prefix_list.s3
    # would otherwise make for an empty vpc_endpoint_prefix_list_ids (see
    # this file's own header comment on why every run here is offline).
    vpc_endpoint_prefix_list_ids  = ["pl-0123456789abcdef0"]
    additional_security_group_ids = ["sg-0123456789abcdef0"]
  }

  assert {
    condition     = contains(aws_lambda_function.main.vpc_config[0].security_group_ids, "sg-lambdaown00000000")
    error_message = "The function's own security group stays attached."
  }

  assert {
    condition     = contains(aws_lambda_function.main.vpc_config[0].security_group_ids, "sg-0123456789abcdef0")
    error_message = "additional_security_group_ids is attached alongside the function's own security group."
  }

  assert {
    condition     = length(aws_lambda_function.main.vpc_config[0].security_group_ids) == 2
    error_message = "Exactly the function's own security group plus additional_security_group_ids -- nothing dropped, nothing extra."
  }
}

run "custom_egress_rule_security_groups_renders_no_cidr_blocks" {
  command = plan

  # Mirrors redis-auth-rotation's HTTPS-to-VPC-endpoints rule in
  # stacks/catalog/templates/microservices-platform.yaml: a custom_egress_rules
  # entry that sets security_groups and omits cidr_blocks entirely must render
  # a security_groups-only egress block, not fall back to an open or CIDR rule.
  variables {
    vpc_id     = "vpc-0123456789abcdef0"
    subnet_ids = ["subnet-0123456789abcdef0"]
    # Set to avoid the real AWS lookup data.aws_ec2_managed_prefix_list.s3
    # would otherwise make for an empty vpc_endpoint_prefix_list_ids (see
    # this file's own header comment on why every run here is offline).
    vpc_endpoint_prefix_list_ids = ["pl-0123456789abcdef0"]
    custom_egress_rules = [
      {
        description     = "HTTPS to the secretsmanager/elasticache VPC endpoints"
        from_port       = 443
        to_port         = 443
        protocol        = "tcp"
        security_groups = ["sg-0123456789abcdef2"]
      }
    ]
  }

  assert {
    condition = anytrue([
      for eg in aws_security_group.lambda[0].egress : (
        eg.from_port == 443
        && eg.to_port == 443
        && eg.protocol == "tcp"
        && eg.security_groups == toset(["sg-0123456789abcdef2"])
        && length(eg.cidr_blocks) == 0
      )
    ])
    error_message = "A custom_egress_rules entry with only security_groups set must render an egress rule whose security_groups contains that SG and whose cidr_blocks is empty, not populated from the security_groups value."
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
