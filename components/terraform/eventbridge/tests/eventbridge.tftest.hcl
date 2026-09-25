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

  # Likewise for aws_lambda_permission.source_arn in the targets apply run.
  mock_resource "aws_cloudwatch_event_rule" {
    defaults = {
      arn = "arn:aws:events:eu-west-2:123456789012:rule/test-microservices/test-user-registered"
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

# --- targets ---------------------------------------------------------------

run "targets_deliver_to_a_queue_and_a_function" {
  command = plan

  variables {
    name           = "user-registered"
    event_bus_name = "test-microservices"
    targets = {
      notifications = {
        arn                = "arn:aws:sqs:eu-west-2:123456789012:test-user-notifications"
        input_path         = "$.detail"
        dead_letter_config = { arn = "arn:aws:sqs:eu-west-2:123456789012:test-event-bus-dlq" }
        retry_policy       = { maximum_event_age_in_seconds = 3600, maximum_retry_attempts = 10 }
      }
      welcome-email = {
        arn = "arn:aws:lambda:eu-west-2:123456789012:function:test-welcome-email"
        input_transformer = {
          input_paths    = { user = "$.detail.userId" }
          input_template = "{\"userId\": <user>}"
        }
      }
    }
  }

  assert {
    condition     = length(aws_cloudwatch_event_target.this) == 2 && length(aws_cloudwatch_event_target.logs) == 1
    error_message = "Each target gets its own aws_cloudwatch_event_target, next to the log group's."
  }

  assert {
    condition = (
      aws_cloudwatch_event_target.this["notifications"].target_id == "notifications"
      && aws_cloudwatch_event_target.this["notifications"].arn == "arn:aws:sqs:eu-west-2:123456789012:test-user-notifications"
      && aws_cloudwatch_event_target.this["notifications"].event_bus_name == "test-microservices"
      && aws_cloudwatch_event_target.this["notifications"].input_path == "$.detail"
    )
    error_message = "The target ID is the map key, and the target sits on the rule's bus with its arn and input_path."
  }

  assert {
    condition = (
      aws_cloudwatch_event_target.this["notifications"].dead_letter_config[0].arn == "arn:aws:sqs:eu-west-2:123456789012:test-event-bus-dlq"
      && aws_cloudwatch_event_target.this["notifications"].retry_policy[0].maximum_event_age_in_seconds == 3600
      && aws_cloudwatch_event_target.this["notifications"].retry_policy[0].maximum_retry_attempts == 10
    )
    error_message = "dead_letter_config and retry_policy are passed through."
  }

  assert {
    condition = (
      aws_cloudwatch_event_target.this["welcome-email"].input_transformer[0].input_paths["user"] == "$.detail.userId"
      && aws_cloudwatch_event_target.this["welcome-email"].input_transformer[0].input_template == "{\"userId\": <user>}"
      && length(aws_cloudwatch_event_target.this["welcome-email"].dead_letter_config) == 0
    )
    error_message = "input_transformer is passed through, and unset blocks stay absent."
  }

  assert {
    condition     = keys(aws_lambda_permission.this) == ["welcome-email"]
    error_message = "Only the Lambda target gets a Lambda permission; the queue relies on its own policy."
  }

  assert {
    condition = (
      aws_lambda_permission.this["welcome-email"].principal == "events.amazonaws.com"
      && aws_lambda_permission.this["welcome-email"].action == "lambda:InvokeFunction"
      && aws_lambda_permission.this["welcome-email"].function_name == "arn:aws:lambda:eu-west-2:123456789012:function:test-welcome-email"
      && aws_lambda_permission.this["welcome-email"].statement_id == "AllowEventBridge-test-user-registered-welcome-email"
    )
    error_message = "EventBridge may invoke the function, under a statement named after the rule and target."
  }
}

run "lambda_permission_is_scoped_to_the_rule" {
  command = apply

  variables {
    name           = "user-registered"
    event_bus_name = "test-microservices"
    targets = {
      welcome-email = { arn = "arn:aws:lambda:eu-west-2:123456789012:function:test-welcome-email" }
    }
  }

  assert {
    condition     = aws_lambda_permission.this["welcome-email"].source_arn == aws_cloudwatch_event_rule.this[0].arn
    error_message = "The function may be invoked by this rule only (source_arn is the rule ARN)."
  }
}

run "fifo_queue_target_gets_a_message_group" {
  command = plan

  variables {
    targets = {
      orders = {
        arn                  = "arn:aws:sqs:eu-west-2:123456789012:test-orders.fifo"
        sqs_message_group_id = "orders"
      }
    }
  }

  assert {
    condition     = aws_cloudwatch_event_target.this["orders"].sqs_target[0].message_group_id == "orders"
    error_message = "sqs_message_group_id becomes the target's sqs_target.message_group_id."
  }
}

run "role_targets_take_a_role" {
  command = plan

  variables {
    targets = {
      workflow = {
        arn      = "arn:aws:states:eu-west-2:123456789012:stateMachine:test-workflow"
        role_arn = "arn:aws:iam::123456789012:role/test-eventbridge-states"
      }
    }
  }

  assert {
    condition     = aws_cloudwatch_event_target.this["workflow"].role_arn == "arn:aws:iam::123456789012:role/test-eventbridge-states" && length(aws_lambda_permission.this) == 0
    error_message = "role_arn is passed through, and a non-Lambda target gets no Lambda permission."
  }
}

run "disabled_creates_no_targets" {
  command = plan

  variables {
    enabled = false
    targets = {
      welcome-email = { arn = "arn:aws:lambda:eu-west-2:123456789012:function:test-welcome-email" }
    }
  }

  assert {
    condition     = length(aws_cloudwatch_event_target.this) == 0 && length(aws_lambda_permission.this) == 0
    error_message = "enabled = false creates no targets and no permissions."
  }
}

run "rejects_a_role_on_a_queue_target" {
  command = plan

  variables {
    targets = {
      q = {
        arn      = "arn:aws:sqs:eu-west-2:123456789012:test-orders"
        role_arn = "arn:aws:iam::123456789012:role/test-role"
      }
    }
  }

  expect_failures = [var.targets]
}

run "rejects_a_state_machine_target_without_a_role" {
  command = plan

  variables {
    targets = {
      workflow = { arn = "arn:aws:states:eu-west-2:123456789012:stateMachine:test-workflow" }
    }
  }

  expect_failures = [var.targets]
}

run "rejects_more_than_four_targets" {
  command = plan

  variables {
    targets = {
      a = { arn = "arn:aws:sqs:eu-west-2:123456789012:a" }
      b = { arn = "arn:aws:sqs:eu-west-2:123456789012:b" }
      c = { arn = "arn:aws:sqs:eu-west-2:123456789012:c" }
      d = { arn = "arn:aws:sqs:eu-west-2:123456789012:d" }
      e = { arn = "arn:aws:sqs:eu-west-2:123456789012:e" }
    }
  }

  expect_failures = [var.targets]
}

run "rejects_the_log_group_target_id" {
  command = plan

  variables {
    targets = {
      cloudwatch-logs = { arn = "arn:aws:sqs:eu-west-2:123456789012:test-orders" }
    }
  }

  expect_failures = [var.targets]
}

run "rejects_input_path_with_input_transformer" {
  command = plan

  variables {
    targets = {
      q = {
        arn               = "arn:aws:sqs:eu-west-2:123456789012:test-orders"
        input_path        = "$.detail"
        input_transformer = { input_template = "\"x\"" }
      }
    }
  }

  expect_failures = [var.targets]
}

run "rejects_a_non_sqs_target_dead_letter_queue" {
  command = plan

  variables {
    targets = {
      q = {
        arn                = "arn:aws:sqs:eu-west-2:123456789012:test-orders"
        dead_letter_config = { arn = "arn:aws:sns:eu-west-2:123456789012:test-topic" }
      }
    }
  }

  expect_failures = [var.targets]
}

run "rejects_an_out_of_range_retry_policy" {
  command = plan

  variables {
    targets = {
      q = {
        arn          = "arn:aws:sqs:eu-west-2:123456789012:test-orders"
        retry_policy = { maximum_retry_attempts = 186 }
      }
    }
  }

  expect_failures = [var.targets]
}

run "rejects_a_message_group_on_a_non_queue_target" {
  command = plan

  variables {
    targets = {
      f = {
        arn                  = "arn:aws:lambda:eu-west-2:123456789012:function:test-fn"
        sqs_message_group_id = "g"
      }
    }
  }

  expect_failures = [var.targets]
}

run "rejects_a_target_that_is_not_an_arn" {
  command = plan

  variables {
    targets = {
      q = { arn = "test-orders" }
    }
  }

  expect_failures = [var.targets]
}
