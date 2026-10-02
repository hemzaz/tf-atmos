# Mock-provider tests for job definitions, their roles and log group: no AWS
# credentials, no network. Run from the component directory with
# `terraform init -backend=false && terraform test`.

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
      arn = "arn:aws:logs:us-east-1:123456789012:log-group:/aws/batch/test-batch"
    }
  }
}

override_resource {
  override_during = plan
  target          = aws_iam_role.job_execution[0]
  values          = { arn = "arn:aws:iam::123456789012:role/test-batch-job-execution" }
}

override_resource {
  override_during = plan
  target          = aws_iam_role.job["etl"]
  values          = { arn = "arn:aws:iam::123456789012:role/test-batch-etl-job", id = "test-batch-etl-job" }
}

variables {
  region          = "us-east-1"
  name            = "batch"
  log_kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"
  tags = {
    Environment = "test"
    Tenant      = "fnx"
    ManagedBy   = "Terraform"
  }
  job_definitions = {
    etl = {
      image   = "123456789012.dkr.ecr.us-east-1.amazonaws.com/etl:1.0"
      vcpu    = 0.5
      memory  = 1024
      command = ["--input", "Ref::input_path"]
      parameters = {
        input_path = "s3://in/"
      }
      environment = {
        ENVIRONMENT = "test"
      }
      job_role_policy_arns = ["arn:aws:iam::123456789012:policy/etl-data"]
      job_role_policy_json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"s3:GetObject\",\"Resource\":\"arn:aws:s3:::in/*\"}]}"
      retry_strategy = {
        attempts = 3
        evaluate_on_exit = [
          { action = "RETRY", on_status_reason = "Host EC2*" },
          { action = "EXIT", on_reason = "*" },
        ]
      }
      timeout_seconds = 3600
    }
    train = {
      platform_capability = "EC2"
      image               = "123456789012.dkr.ecr.us-east-1.amazonaws.com/train:1.0"
      vcpu                = 8
      memory              = 32768
      gpu                 = 1
      ulimits             = [{ name = "nofile", soft_limit = 65536, hard_limit = 65536 }]
      linux_parameters = {
        shared_memory_size = 4096
        devices            = [{ host_path = "/dev/nvidia0", permissions = ["READ", "WRITE"] }]
      }
      log_stream_prefix = "ml-training"
    }
  }
}

run "fargate_definition_defaults" {
  command = plan

  assert {
    condition = (
      aws_batch_job_definition.this["etl"].name == "test-batch-etl"
      && aws_batch_job_definition.this["etl"].type == "container"
      && aws_batch_job_definition.this["etl"].platform_capabilities == toset(["FARGATE"])
      && aws_batch_job_definition.this["etl"].propagate_tags
    )
    error_message = "A job definition is a FARGATE container definition named <Environment>-<name>-<key>, propagating tags."
  }

  assert {
    condition = (
      jsondecode(aws_batch_job_definition.this["etl"].container_properties).networkConfiguration.assignPublicIp == "DISABLED"
      && jsondecode(aws_batch_job_definition.this["etl"].container_properties).fargatePlatformConfiguration.platformVersion == "LATEST"
      && jsondecode(aws_batch_job_definition.this["etl"].container_properties).readonlyRootFilesystem
      && !can(jsondecode(aws_batch_job_definition.this["etl"].container_properties).privileged)
    )
    error_message = "Fargate defaults: no public IP, LATEST platform, read-only root filesystem, no privileged key."
  }

  assert {
    condition = jsondecode(aws_batch_job_definition.this["etl"].container_properties).resourceRequirements == [
      { type = "VCPU", value = "0.5" }, { type = "MEMORY", value = "1024" },
    ]
    error_message = "vcpu and memory become resourceRequirements strings."
  }

  assert {
    condition = (
      jsondecode(aws_batch_job_definition.this["etl"].container_properties).command == ["--input", "Ref::input_path"]
      && jsondecode(aws_batch_job_definition.this["etl"].container_properties).environment == [{ name = "ENVIRONMENT", value = "test" }]
      && aws_batch_job_definition.this["etl"].parameters == tomap({ input_path = "s3://in/" })
    )
    error_message = "command, environment and parameters pass through."
  }

  assert {
    condition = (
      aws_batch_job_definition.this["etl"].retry_strategy[0].attempts == 3
      && length(aws_batch_job_definition.this["etl"].retry_strategy[0].evaluate_on_exit) == 2
      && aws_batch_job_definition.this["etl"].timeout[0].attempt_duration_seconds == 3600
    )
    error_message = "retry_strategy and timeout pass through."
  }

  assert {
    condition     = length(aws_batch_job_definition.this["train"].timeout) == 0 && aws_batch_job_definition.this["train"].retry_strategy[0].attempts == 1
    error_message = "Without timeout_seconds there is no timeout; retry attempts default to 1."
  }
}

run "ec2_definition_takes_ec2_only_settings" {
  command = plan

  assert {
    condition = (
      jsondecode(aws_batch_job_definition.this["train"].container_properties).resourceRequirements == [
        { type = "VCPU", value = "8" }, { type = "MEMORY", value = "32768" }, { type = "GPU", value = "1" },
      ]
      && !contains(keys(jsondecode(aws_batch_job_definition.this["train"].container_properties)), "privileged")
      && jsondecode(aws_batch_job_definition.this["train"].container_properties).ulimits == [{ name = "nofile", softLimit = 65536, hardLimit = 65536 }]
      && jsondecode(aws_batch_job_definition.this["train"].container_properties).linuxParameters == {
        sharedMemorySize = 4096
        devices          = [{ hostPath = "/dev/nvidia0", permissions = ["READ", "WRITE"] }]
      }
    )
    error_message = "EC2 definitions take gpu, ulimits and linux_parameters; privileged false is not sent."
  }

  assert {
    condition = alltrue([for key in ["networkConfiguration", "fargatePlatformConfiguration", "executionRoleArn", "jobRoleArn"] :
      !contains(keys(jsondecode(aws_batch_job_definition.this["train"].container_properties)), key)
    ])
    error_message = "An EC2 definition without secrets or job role policies gets no Fargate settings, execution role or job role."
  }
}

run "ec2_privileged_true_is_sent" {
  command = plan

  variables {
    job_definitions = { train = { platform_capability = "EC2", image = "train:1.0", vcpu = 1, memory = 1024, privileged = true } }
  }

  assert {
    condition     = jsondecode(aws_batch_job_definition.this["train"].container_properties).privileged == true
    error_message = "privileged = true on an EC2 definition is sent."
  }
}

run "log_group_is_encrypted_and_the_default_destination" {
  command = plan

  assert {
    condition = (
      aws_cloudwatch_log_group.jobs[0].name == "/aws/batch/test-batch"
      && aws_cloudwatch_log_group.jobs[0].kms_key_id == var.log_kms_key_arn
      && aws_cloudwatch_log_group.jobs[0].retention_in_days == 90
      && output.log_group_name == "/aws/batch/test-batch"
    )
    error_message = "The job log group is /aws/batch/<Environment>-<name>, KMS-encrypted, 90-day retention."
  }

  assert {
    condition = (
      jsondecode(aws_batch_job_definition.this["etl"].container_properties).logConfiguration == {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/aws/batch/test-batch"
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "etl"
        }
      }
      && jsondecode(aws_batch_job_definition.this["train"].container_properties).logConfiguration.options["awslogs-stream-prefix"] == "ml-training"
    )
    error_message = "Definitions log to the component log group with the key (or log_stream_prefix) as stream prefix."
  }
}

run "execution_role_is_created_for_fargate_and_scoped" {
  command = plan

  assert {
    condition = (
      aws_iam_role.job_execution[0].name == "test-batch-job-execution"
      && jsondecode(aws_batch_job_definition.this["etl"].container_properties).executionRoleArn == "arn:aws:iam::123456789012:role/test-batch-job-execution"
      && output.job_execution_role_arn == "arn:aws:iam::123456789012:role/test-batch-job-execution"
    )
    error_message = "A FARGATE definition gets the created <Environment>-<name>-job-execution role."
  }

  assert {
    condition = jsondecode(aws_iam_role.job_execution[0].assume_role_policy).Statement[0] == {
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Condition = {
        StringEquals = { "aws:SourceAccount" = "123456789012" }
      }
    }
    error_message = "The execution role trusts ecs-tasks limited by aws:SourceAccount only (no SourceArn, which the execution role docs do not show)."
  }

  assert {
    condition = {
      for s in jsondecode(aws_iam_role_policy.job_execution[0].policy).Statement : s.Sid => s.Resource
      } == {
      ECRAuthorization = "*"
      ECRPull          = ["*"]
      Logs             = "arn:aws:logs:us-east-1:123456789012:log-group:/aws/batch/test-batch:log-stream:*"
    }
    error_message = "Without secrets the execution role has ECR pull (every repository by default) and log streams in the component log group only."
  }
}

run "secrets_grant_exactly_their_arns" {
  command = plan

  variables {
    ecr_repository_arns = ["arn:aws:ecr:us-east-1:123456789012:repository/etl"]
    secrets_kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/99999999-2222-3333-4444-555555555555"
    job_definitions = {
      etl = {
        image  = "123456789012.dkr.ecr.us-east-1.amazonaws.com/etl:1.0"
        vcpu   = 1
        memory = 2048
        secrets = {
          DB_PASSWORD = "arn:aws:secretsmanager:us-east-1:123456789012:secret:db-AbCdEf:password::"
          DB_USER     = "arn:aws:secretsmanager:us-east-1:123456789012:secret:db-AbCdEf:username::"
          API_TOKEN   = "arn:aws:ssm:us-east-1:123456789012:parameter/etl/api-token"
        }
      }
    }
  }

  assert {
    condition = {
      for s in jsondecode(aws_iam_role_policy.job_execution[0].policy).Statement : s.Sid => s.Resource
      } == {
      ECRAuthorization = "*"
      ECRPull          = ["arn:aws:ecr:us-east-1:123456789012:repository/etl"]
      Logs             = "arn:aws:logs:us-east-1:123456789012:log-group:/aws/batch/test-batch:log-stream:*"
      SecretsManager   = ["arn:aws:secretsmanager:us-east-1:123456789012:secret:db-AbCdEf"]
      SSMParameters    = ["arn:aws:ssm:us-east-1:123456789012:parameter/etl/api-token"]
      SecretsKMS       = "arn:aws:kms:us-east-1:123456789012:key/99999999-2222-3333-4444-555555555555"
    }
    error_message = "Secrets grants are scoped to the secret ARN (without the json-key tail), the parameter ARN, the given repositories and the secrets key."
  }

  assert {
    condition = [
      for s in jsondecode(aws_iam_role_policy.job_execution[0].policy).Statement : s.Condition if s.Sid == "SecretsKMS"
      ] == [{
        StringEquals = { "kms:ViaService" = ["secretsmanager.us-east-1.amazonaws.com", "ssm.us-east-1.amazonaws.com"] }
    }]
    error_message = "kms:Decrypt on the secrets key is limited to Secrets Manager and SSM."
  }

  assert {
    condition = jsondecode(aws_batch_job_definition.this["etl"].container_properties).secrets == [
      { name = "API_TOKEN", valueFrom = "arn:aws:ssm:us-east-1:123456789012:parameter/etl/api-token" },
      { name = "DB_PASSWORD", valueFrom = "arn:aws:secretsmanager:us-east-1:123456789012:secret:db-AbCdEf:password::" },
      { name = "DB_USER", valueFrom = "arn:aws:secretsmanager:us-east-1:123456789012:secret:db-AbCdEf:username::" },
    ]
    error_message = "Secrets pass through as name/valueFrom pairs."
  }
}

run "ec2_secrets_get_an_execution_role_without_ecr" {
  command = plan

  variables {
    job_definitions = {
      train = {
        platform_capability = "EC2"
        image               = "train:1.0"
        vcpu                = 2
        memory              = 4096
        secrets             = { TOKEN = "arn:aws:ssm:us-east-1:123456789012:parameter/train/token" }
      }
    }
  }

  assert {
    condition = (
      jsondecode(aws_batch_job_definition.this["train"].container_properties).executionRoleArn == "arn:aws:iam::123456789012:role/test-batch-job-execution"
      && [for s in jsondecode(aws_iam_role_policy.job_execution[0].policy).Statement : s.Sid] == ["Logs", "SSMParameters"]
    )
    error_message = "An EC2 definition with secrets gets the execution role, without ECR statements (the instance role pulls)."
  }
}

run "job_role_is_created_from_policies" {
  command = plan

  assert {
    condition = (
      aws_iam_role.job["etl"].name == "test-batch-etl-job"
      && jsondecode(aws_iam_role.job["etl"].assume_role_policy).Statement[0] == {
        Effect    = "Allow"
        Action    = "sts:AssumeRole"
        Principal = { Service = "ecs-tasks.amazonaws.com" }
        Condition = {
          StringEquals = { "aws:SourceAccount" = "123456789012" }
          ArnLike      = { "aws:SourceArn" = "arn:aws:ecs:us-east-1:123456789012:*" }
        }
      }
      && aws_iam_role_policy_attachment.job["etl:arn:aws:iam::123456789012:policy/etl-data"].policy_arn == "arn:aws:iam::123456789012:policy/etl-data"
      && jsondecode(aws_iam_role_policy.job["etl"].policy).Statement[0].Action == "s3:GetObject"
    )
    error_message = "job_role_policy_arns and job_role_policy_json create <Environment>-<name>-<key>-job with the ecs-tasks trust."
  }

  assert {
    condition = (
      jsondecode(aws_batch_job_definition.this["etl"].container_properties).jobRoleArn == "arn:aws:iam::123456789012:role/test-batch-etl-job"
      && output.job_role_arns == { etl = "arn:aws:iam::123456789012:role/test-batch-etl-job" }
      && !contains(keys(aws_iam_role.job), "train")
    )
    error_message = "Only definitions with job role policies get a created job role."
  }
}

run "override_roles_create_none" {
  command = plan

  variables {
    execution_role_arn = "arn:aws:iam::123456789012:role/shared-execution"
    job_definitions = {
      etl = {
        image        = "etl:1.0"
        vcpu         = 0.25
        memory       = 512
        job_role_arn = "arn:aws:iam::123456789012:role/shared-job"
      }
    }
  }

  assert {
    condition = (
      length(aws_iam_role.job_execution) == 0 && length(aws_iam_role_policy.job_execution) == 0 && length(aws_iam_role.job) == 0
      && jsondecode(aws_batch_job_definition.this["etl"].container_properties).executionRoleArn == "arn:aws:iam::123456789012:role/shared-execution"
      && jsondecode(aws_batch_job_definition.this["etl"].container_properties).jobRoleArn == "arn:aws:iam::123456789012:role/shared-job"
      && output.job_execution_role_arn == "arn:aws:iam::123456789012:role/shared-execution"
      && output.job_role_arns == { etl = "arn:aws:iam::123456789012:role/shared-job" }
    )
    error_message = "execution_role_arn and job_role_arn are used as given and no roles are created."
  }
}

run "fargate_settings_pass_through" {
  command = plan

  variables {
    job_definitions = {
      arm = {
        image                    = "arm:1.0"
        vcpu                     = 16
        memory                   = 122880
        fargate_platform_version = "1.4.0"
        assign_public_ip         = "ENABLED"
        ephemeral_storage_gib    = 100
        cpu_architecture         = "ARM64"
        readonly_root_filesystem = false
        user                     = "1000"
        scheduling_priority      = 10
        propagate_tags           = false
      }
    }
  }

  assert {
    condition = (
      jsondecode(aws_batch_job_definition.this["arm"].container_properties).networkConfiguration.assignPublicIp == "ENABLED"
      && jsondecode(aws_batch_job_definition.this["arm"].container_properties).fargatePlatformConfiguration.platformVersion == "1.4.0"
      && jsondecode(aws_batch_job_definition.this["arm"].container_properties).ephemeralStorage.sizeInGiB == 100
      && jsondecode(aws_batch_job_definition.this["arm"].container_properties).runtimePlatform == { cpuArchitecture = "ARM64", operatingSystemFamily = "LINUX" }
      && !contains(keys(jsondecode(aws_batch_job_definition.this["arm"].container_properties)), "readonlyRootFilesystem")
      && jsondecode(aws_batch_job_definition.this["arm"].container_properties).user == "1000"
      && aws_batch_job_definition.this["arm"].scheduling_priority == 10
      && !aws_batch_job_definition.this["arm"].propagate_tags
    )
    error_message = "Fargate settings, user, scheduling_priority and propagate_tags pass through."
  }
}

run "no_job_definitions_create_no_job_resources" {
  command = plan

  variables {
    log_kms_key_arn = null
    job_definitions = {}
  }

  assert {
    condition = (
      length(aws_cloudwatch_log_group.jobs) == 0 && length(aws_iam_role.job_execution) == 0
      && length(aws_batch_job_definition.this) == 0 && output.log_group_name == null
      && output.job_execution_role_arn == null && output.job_definition_arns == {}
    )
    error_message = "Without job definitions there is no log group, execution role or definition, and no log key is needed."
  }
}

run "disabled_creates_no_job_resources" {
  command = plan

  variables {
    enabled = false
  }

  assert {
    condition     = length(aws_batch_job_definition.this) == 0 && length(aws_cloudwatch_log_group.jobs) == 0 && length(aws_iam_role.job) == 0 && length(aws_iam_role.job_execution) == 0
    error_message = "enabled = false creates no job resources."
  }
}

# Negative validations.

run "fargate_rejects_an_unsupported_vcpu_memory_pair" {
  command = plan

  variables {
    job_definitions = { etl = { image = "etl:1.0", vcpu = 1, memory = 1024 } }
  }

  expect_failures = [var.job_definitions]
}

run "fargate_rejects_an_unsupported_vcpu" {
  command = plan

  variables {
    job_definitions = { etl = { image = "etl:1.0", vcpu = 3, memory = 8192 } }
  }

  expect_failures = [var.job_definitions]
}

run "fargate_rejects_privileged" {
  command = plan

  variables {
    job_definitions = { etl = { image = "etl:1.0", vcpu = 1, memory = 2048, privileged = true } }
  }

  expect_failures = [var.job_definitions]
}

run "fargate_rejects_gpu" {
  command = plan

  variables {
    job_definitions = { etl = { image = "etl:1.0", vcpu = 1, memory = 2048, gpu = 1 } }
  }

  expect_failures = [var.job_definitions]
}

run "ec2_rejects_a_fractional_vcpu" {
  command = plan

  variables {
    job_definitions = { train = { platform_capability = "EC2", image = "train:1.0", vcpu = 0.5, memory = 1024 } }
  }

  expect_failures = [var.job_definitions]
}

run "ec2_rejects_memory_below_4" {
  command = plan

  variables {
    job_definitions = { train = { platform_capability = "EC2", image = "train:1.0", vcpu = 1, memory = 2 } }
  }

  expect_failures = [var.job_definitions]
}

run "ec2_rejects_fargate_settings" {
  command = plan

  variables {
    job_definitions = { train = { platform_capability = "EC2", image = "train:1.0", vcpu = 1, memory = 1024, assign_public_ip = "DISABLED" } }
  }

  expect_failures = [var.job_definitions]
}

run "empty_image_is_rejected" {
  command = plan

  variables {
    job_definitions = { etl = { image = " ", vcpu = 1, memory = 2048 } }
  }

  expect_failures = [var.job_definitions]
}

run "retry_attempts_above_10_are_rejected" {
  command = plan

  variables {
    job_definitions = { etl = { image = "etl:1.0", vcpu = 1, memory = 2048, retry_strategy = { attempts = 11 } } }
  }

  expect_failures = [var.job_definitions]
}

run "evaluate_on_exit_needs_a_match" {
  command = plan

  variables {
    job_definitions = { etl = { image = "etl:1.0", vcpu = 1, memory = 2048, retry_strategy = { attempts = 2, evaluate_on_exit = [{ action = "RETRY" }] } } }
  }

  expect_failures = [var.job_definitions]
}

run "timeout_below_60_is_rejected" {
  command = plan

  variables {
    job_definitions = { etl = { image = "etl:1.0", vcpu = 1, memory = 2048, timeout_seconds = 30 } }
  }

  expect_failures = [var.job_definitions]
}

run "secret_names_are_rejected" {
  command = plan

  variables {
    job_definitions = { etl = { image = "etl:1.0", vcpu = 1, memory = 2048, secrets = { DB_PASSWORD = "db-password" } } }
  }

  expect_failures = [var.job_definitions]
}

run "secret_arns_without_the_suffix_are_rejected" {
  command = plan

  variables {
    job_definitions = { etl = { image = "etl:1.0", vcpu = 1, memory = 2048, secrets = { DB_PASSWORD = "arn:aws:secretsmanager:us-east-1:123456789012:secret:db" } } }
  }

  expect_failures = [var.job_definitions]
}

run "evaluate_on_exit_rejects_a_leading_wildcard" {
  command = plan

  variables {
    job_definitions = { etl = { image = "etl:1.0", vcpu = 1, memory = 2048, retry_strategy = { attempts = 2, evaluate_on_exit = [{ action = "EXIT", on_reason = "*error*" }] } } }
  }

  expect_failures = [var.job_definitions]
}

run "evaluate_on_exit_rejects_a_non_numeric_exit_code" {
  command = plan

  variables {
    job_definitions = { etl = { image = "etl:1.0", vcpu = 1, memory = 2048, retry_strategy = { attempts = 2, evaluate_on_exit = [{ action = "RETRY", on_exit_code = "1a" }] } } }
  }

  expect_failures = [var.job_definitions]
}

run "job_role_arn_excludes_job_role_policies" {
  command = plan

  variables {
    job_definitions = {
      etl = {
        image                = "etl:1.0"
        vcpu                 = 1
        memory               = 2048
        job_role_arn         = "arn:aws:iam::123456789012:role/shared-job"
        job_role_policy_arns = ["arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"]
      }
    }
  }

  expect_failures = [var.job_definitions]
}

run "job_definitions_need_a_log_key" {
  command = plan

  variables {
    log_kms_key_arn = null
  }

  expect_failures = [var.log_kms_key_arn]
}
