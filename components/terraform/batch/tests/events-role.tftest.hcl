# Mock-provider tests for the EventBridge target role (events_role_enabled):
# no AWS credentials, no network. Run from the component directory with
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
}

override_resource {
  override_during = plan
  target          = aws_batch_job_queue.this["default"]
  values          = { arn = "arn:aws:batch:us-east-1:123456789012:job-queue/test-batch-default" }
}

override_resource {
  override_during = plan
  target          = aws_batch_job_definition.this["etl"]
  values          = { arn_prefix = "arn:aws:batch:us-east-1:123456789012:job-definition/test-batch-etl" }
}

override_resource {
  override_during = plan
  target          = aws_iam_role.events[0]
  values          = { arn = "arn:aws:iam::123456789012:role/test-batch-events", id = "test-batch-events" }
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
  compute_environments = {
    fargate = {
      max_vcpus          = 16
      subnet_ids         = ["subnet-0123456789abcdef0"]
      security_group_ids = ["sg-0123456789abcdef0"]
    }
  }
  job_queues = {
    default = {
      compute_environment_order = [{ order = 1, compute_environment = "fargate" }]
    }
  }
  job_definitions = {
    etl = {
      image  = "123456789012.dkr.ecr.us-east-1.amazonaws.com/etl:1.0"
      vcpu   = 1
      memory = 2048
    }
  }
}

run "events_role_off_by_default" {
  command = plan

  assert {
    condition     = length(aws_iam_role.events) == 0 && length(aws_iam_role_policy.events) == 0 && output.events_role_arn == null
    error_message = "No events role unless events_role_enabled."
  }
}

run "events_role_scoped_to_this_instance" {
  command = plan

  variables {
    events_role_enabled = true
  }

  assert {
    condition = (
      aws_iam_role.events[0].name == "test-batch-events"
      && jsondecode(aws_iam_role.events[0].assume_role_policy).Statement[0].Principal.Service == "events.amazonaws.com"
      && jsondecode(aws_iam_role.events[0].assume_role_policy).Statement[0].Condition.StringEquals["aws:SourceAccount"] == "123456789012"
    )
    error_message = "The events role is <Environment>-<name>-events, trusted by events.amazonaws.com from this account."
  }

  assert {
    condition = (
      jsondecode(aws_iam_role_policy.events[0].policy).Statement[0].Action == "batch:SubmitJob"
      && toset(jsondecode(aws_iam_role_policy.events[0].policy).Statement[0].Resource) == toset([
        "arn:aws:batch:us-east-1:123456789012:job-queue/test-batch-default",
        "arn:aws:batch:us-east-1:123456789012:job-definition/test-batch-etl:*",
      ])
    )
    error_message = "The events role may only submit this instance's job definitions (any revision) to its job queues."
  }

  assert {
    condition     = output.events_role_arn == "arn:aws:iam::123456789012:role/test-batch-events"
    error_message = "events_role_arn outputs the created role."
  }
}

run "events_role_rejects_no_job_definitions" {
  command = plan

  variables {
    events_role_enabled = true
    job_definitions     = {}
  }

  expect_failures = [var.events_role_enabled]
}

run "events_role_rejects_no_job_queues" {
  command = plan

  variables {
    events_role_enabled = true
    job_queues          = {}
  }

  expect_failures = [var.events_role_enabled]
}
