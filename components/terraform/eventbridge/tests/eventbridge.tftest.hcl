# Mock-provider tests: no AWS credentials, no network. Run from the component
# directory with `terraform init -backend=false && terraform test`.

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  # A well-formed ARN, needed only for the one run below that applies (and so
  # resolves this otherwise-unknown-until-apply attribute): the mocked value
  # is fed into aws_cloudwatch_log_resource_policy.resource_arn and
  # aws_cloudwatch_event_target.arn, both of which validate the ARN format.
  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:eu-west-2:123456789012:log-group:/aws/events/mock"
    }
  }
}

variables {
  region      = "eu-west-2"
  name        = "audit"
  kms_key_arn = "arn:aws:kms:eu-west-2:123456789012:key/00000000-0000-0000-0000-000000000000"
  tags = {
    Environment = "test"
    Tenant      = "fnx"
    ManagedBy   = "Terraform"
  }
}

run "defaults_put_a_logged_rule_on_the_default_bus" {
  command = plan

  assert {
    condition     = aws_cloudwatch_event_rule.this[0].event_bus_name == "default"
    error_message = "Without create_event_bus the rule sits on the default bus, as in Cloud Posse."
  }

  assert {
    condition     = jsondecode(aws_cloudwatch_event_rule.this[0].event_pattern) == { source = ["aws.ec2"] }
    error_message = "The default pattern is Cloud Posse's { source = [aws.ec2] }."
  }

  assert {
    condition     = aws_cloudwatch_event_rule.this[0].description == "test-audit"
    error_message = "An empty description defaults to <Environment>-<name>."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this[0].name == "/aws/events/test-audit"
    error_message = "EventBridge only delivers to log groups under /aws/events/."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this[0].kms_key_id == var.kms_key_arn && aws_cloudwatch_log_group.this[0].retention_in_days == 3
    error_message = "The log group is encrypted with the given key and keeps Cloud Posse's 3-day retention."
  }

  assert {
    condition     = length(aws_cloudwatch_event_bus.this) == 0 && length(aws_cloudwatch_event_archive.this) == 0
    error_message = "No bus or archive unless asked for."
  }

  assert {
    condition     = length(aws_cloudwatch_log_resource_policy.this) == 1 && aws_cloudwatch_event_target.logs[0].event_bus_name == "default"
    error_message = "The log target and the resource policy that lets EventBridge write are created with the rule."
  }

  assert {
    condition     = output.event_bus_name == "default"
    error_message = "event_bus_name reports the bus the rule is on."
  }
}

run "custom_bus_with_archive" {
  command = plan

  variables {
    name                   = "microservices"
    create_event_bus       = true
    archive_enabled        = true
    archive_retention_days = 90
    cloudwatch_event_rule_pattern = {
      source = [{ prefix = "microservices." }]
    }
  }

  assert {
    condition     = aws_cloudwatch_event_bus.this[0].name == "test-microservices" && aws_cloudwatch_event_bus.this[0].kms_key_identifier == var.kms_key_arn
    error_message = "The bus is <Environment>-<name>, encrypted with the given key."
  }

  assert {
    condition     = aws_cloudwatch_event_rule.this[0].event_bus_name == "test-microservices" && aws_cloudwatch_event_target.logs[0].event_bus_name == "test-microservices"
    error_message = "The rule and its target sit on the created bus."
  }

  assert {
    condition     = aws_cloudwatch_event_archive.this[0].retention_days == 90 && aws_cloudwatch_event_archive.this[0].kms_key_identifier == var.kms_key_arn
    error_message = "The archive keeps archive_retention_days and is encrypted with the given key."
  }

  assert {
    condition     = jsondecode(aws_cloudwatch_event_rule.this[0].event_pattern) == { source = [{ prefix = "microservices." }] }
    error_message = "The pattern is passed through as JSON."
  }

  assert {
    condition     = output.event_bus_name == "test-microservices"
    error_message = "event_bus_name reports the created bus."
  }
}

run "rule_on_another_instances_bus" {
  command = plan

  variables {
    event_bus_name = "test-microservices"
  }

  assert {
    condition     = aws_cloudwatch_event_rule.this[0].event_bus_name == "test-microservices" && length(aws_cloudwatch_event_bus.this) == 0
    error_message = "event_bus_name puts the rule on an existing bus without creating one."
  }
}

run "disabled_creates_nothing" {
  command = plan

  variables {
    enabled          = false
    create_event_bus = true
  }

  assert {
    condition     = length(aws_cloudwatch_event_rule.this) == 0 && length(aws_cloudwatch_event_bus.this) == 0 && length(aws_cloudwatch_log_group.this) == 0
    error_message = "enabled = false must create nothing."
  }

  assert {
    condition     = output.event_bus_name == null && output.cloudwatch_event_rule_arn == null
    error_message = "Outputs are null when disabled."
  }
}

run "rejects_an_archive_without_a_bus" {
  command = plan

  variables {
    archive_enabled = true
  }

  expect_failures = [var.archive_enabled]
}

run "rejects_a_non_kms_key" {
  command = plan

  variables {
    kms_key_arn = "alias/aws/events"
  }

  expect_failures = [var.kms_key_arn]
}

run "rejects_an_unsupported_retention" {
  command = plan

  variables {
    event_log_retention_in_days = 2
  }

  expect_failures = [var.event_log_retention_in_days]
}

run "log_resource_policy_is_scoped_to_the_log_group" {
  command = apply

  assert {
    condition     = aws_cloudwatch_log_resource_policy.this[0].policy_name == null
    error_message = "The policy must not be account-scoped (policy_name), which shares a 10-per-region quota with every other component."
  }

  assert {
    condition     = aws_cloudwatch_log_resource_policy.this[0].resource_arn == aws_cloudwatch_log_group.this[0].arn
    error_message = "The policy must be resource-scoped to this instance's log group (resource_arn), consuming none of the account quota."
  }
}

run "custom_bus_wires_a_dead_letter_queue" {
  command = plan

  variables {
    name              = "microservices"
    create_event_bus  = true
    event_bus_dlq_arn = "arn:aws:sqs:eu-west-2:123456789012:microservices-eventbridge-dlq"
  }

  assert {
    condition     = length(aws_cloudwatch_event_bus.this[0].dead_letter_config) == 1
    error_message = "event_bus_dlq_arn must add a dead_letter_config block to the created bus."
  }

  assert {
    condition     = aws_cloudwatch_event_bus.this[0].dead_letter_config[0].arn == var.event_bus_dlq_arn
    error_message = "dead_letter_config.arn must be the given DLQ ARN."
  }
}

run "custom_bus_without_a_dlq_has_no_dead_letter_config" {
  command = plan

  variables {
    name             = "microservices"
    create_event_bus = true
  }

  assert {
    condition     = length(aws_cloudwatch_event_bus.this[0].dead_letter_config) == 0
    error_message = "Without event_bus_dlq_arn the bus must have no dead_letter_config block."
  }
}

run "rejects_a_non_sqs_dlq_arn" {
  command = plan

  variables {
    name              = "microservices"
    create_event_bus  = true
    event_bus_dlq_arn = "arn:aws:sns:eu-west-2:123456789012:not-a-queue"
  }

  expect_failures = [var.event_bus_dlq_arn]
}

run "rejects_an_archive_name_over_48_characters" {
  command = plan

  variables {
    name             = "microservices-event-archive-01"
    create_event_bus = true
    archive_enabled  = true
    tags = {
      Environment = "an-environment-name"
      Tenant      = "fnx"
      ManagedBy   = "Terraform"
    }
  }

  expect_failures = [aws_cloudwatch_event_archive.this[0]]
}
