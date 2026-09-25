# Mock-provider tests: no AWS credentials, no network. Run from the component
# directory with `terraform init -backend=false && terraform test`.

mock_provider "aws" {
  # arn is Computed-only, so it is unknown-until-apply on the real resource;
  # mocking it lets plan-only runs assert on log_destination and (for
  # aws_sfn_state_machine) the events role's scoped policy.
  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:eu-west-2:123456789012:log-group:/aws/vendedlogs/states/test-order-fulfilment"
    }
  }

  # role_arn's schema validates ARN format, which a mock apply run's random
  # default id would fail.
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/mock"
    }
  }

  mock_resource "aws_sfn_state_machine" {
    defaults = {
      arn = "arn:aws:states:eu-west-2:123456789012:stateMachine:test-order-fulfilment"
    }
  }
}

variables {
  region = "eu-west-2"
  name   = "order-fulfilment"
  definition = {
    Comment = "Order fulfilment workflow"
    StartAt = "ProcessOrder"
    States = {
      ProcessOrder = {
        Type     = "Task"
        Resource = "arn:aws:lambda:eu-west-2:123456789012:function:test-order-processor"
        End      = true
      }
    }
  }
  kms_key_arn = "arn:aws:kms:eu-west-2:123456789012:key/00000000-0000-0000-0000-000000000000"
  tags = {
    Environment = "test"
    Tenant      = "fnx"
    ManagedBy   = "Terraform"
  }
}

run "defaults_create_a_standard_machine_with_no_logging" {
  command = plan

  assert {
    condition     = aws_sfn_state_machine.this[0].type == "STANDARD"
    error_message = "type defaults to STANDARD."
  }

  assert {
    condition     = jsondecode(aws_sfn_state_machine.this[0].definition) == var.definition
    error_message = "The definition must be jsonencoded as given."
  }

  assert {
    condition     = aws_sfn_state_machine.this[0].name == "test-order-fulfilment"
    error_message = "The state machine is named <Environment>-<name>."
  }

  assert {
    condition     = length(aws_iam_role_policy.logging) == 0
    error_message = "Without a logging level (default OFF) no logging permissions are attached."
  }

  assert {
    condition     = aws_sfn_state_machine.this[0].logging_configuration[0].log_destination == null
    error_message = "With level OFF the state machine gets no log_destination."
  }

  assert {
    condition     = length(aws_iam_role.events) == 0
    error_message = "No events role unless events_role_enabled."
  }

  assert {
    condition     = output.events_role_arn == null
    error_message = "events_role_arn is null unless events_role_enabled."
  }
}

run "the_log_group_is_always_created_on_the_given_key" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_group.this[0].name == "/aws/vendedlogs/states/test-order-fulfilment"
    error_message = "The log group sits under /aws/vendedlogs/states/, the prefix Step Functions requires."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this[0].kms_key_id == var.kms_key_arn
    error_message = "The log group is encrypted with the given key."
  }

  assert {
    condition     = output.log_group_name == "/aws/vendedlogs/states/test-order-fulfilment"
    error_message = "log_group_name reports the created log group, regardless of the logging level."
  }
}

run "the_execution_role_trust_is_scoped_to_this_machine" {
  command = plan

  assert {
    condition = jsondecode(aws_iam_role.this[0].assume_role_policy).Statement[0].Principal.Service == "states.amazonaws.com"
    error_message = "The role trusts states.amazonaws.com."
  }

  assert {
    condition     = jsondecode(aws_iam_role.this[0].assume_role_policy).Statement[0].Condition.StringEquals["aws:SourceAccount"] == data.aws_caller_identity.current.account_id
    error_message = "The trust policy conditions on aws:SourceAccount."
  }

  assert {
    condition     = jsondecode(aws_iam_role.this[0].assume_role_policy).Statement[0].Condition.StringEquals["aws:SourceArn"] == "arn:aws:states:${var.region}:${data.aws_caller_identity.current.account_id}:stateMachine:test-order-fulfilment"
    error_message = "The trust policy conditions on aws:SourceArn, scoped to this state machine."
  }
}

run "logging_level_wires_the_log_delivery_permissions_and_destination" {
  # apply: log_destination compares against the log group's arn, which (like
  # eventbridge's own log group tests) is unknown until apply even with the
  # mock default above.
  command = apply

  variables {
    logging_configuration = {
      level                  = "ERROR"
      include_execution_data = true
    }
  }

  assert {
    condition     = length(aws_iam_role_policy.logging) == 1
    error_message = "A non-OFF level attaches the log-delivery permissions the execution role needs."
  }

  assert {
    condition     = aws_sfn_state_machine.this[0].logging_configuration[0].level == "ERROR" && aws_sfn_state_machine.this[0].logging_configuration[0].include_execution_data == true
    error_message = "level and include_execution_data are passed through."
  }

  assert {
    condition     = aws_sfn_state_machine.this[0].logging_configuration[0].log_destination == "${aws_cloudwatch_log_group.this[0].arn}:*"
    error_message = "A non-OFF level sets log_destination to the log group."
  }
}

run "tracing_enabled_wires_the_xray_permissions" {
  command = plan

  variables {
    tracing_enabled = true
  }

  assert {
    condition     = aws_sfn_state_machine.this[0].tracing_configuration[0].enabled == true
    error_message = "tracing_configuration.enabled is passed through."
  }

  assert {
    condition     = length(aws_iam_role_policy.tracing) == 1
    error_message = "tracing_enabled attaches the X-Ray write permissions the execution role needs."
  }
}

run "iam_policies_become_one_custom_inline_policy" {
  command = plan

  variables {
    iam_policies = [
      {
        sid       = "InvokeOrderProcessor"
        actions   = ["lambda:InvokeFunction"]
        resources = ["arn:aws:lambda:eu-west-2:123456789012:function:test-order-processor"]
      },
      {
        sid       = "PublishNotifications"
        actions   = ["sns:Publish"]
        resources = ["arn:aws:sns:eu-west-2:123456789012:test-notifications"]
      }
    ]
  }

  assert {
    condition     = length(aws_iam_role_policy.custom) == 1
    error_message = "iam_policies attaches exactly one custom inline policy."
  }
}

run "events_role_is_created_only_when_enabled_and_scoped_to_the_machine" {
  command = apply

  variables {
    events_role_enabled = true
  }

  assert {
    condition = jsondecode(aws_iam_role.events[0].assume_role_policy).Statement[0].Principal.Service == "events.amazonaws.com"
    error_message = "The events role trusts events.amazonaws.com."
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.events_invoke[0].policy).Statement[0].Action == "states:StartExecution"
    error_message = "The events role may only StartExecution."
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.events_invoke[0].policy).Statement[0].Resource == aws_sfn_state_machine.this[0].arn
    error_message = "states:StartExecution is scoped to this state machine only."
  }

  assert {
    condition     = output.events_role_arn == aws_iam_role.events[0].arn
    error_message = "events_role_arn reports the created role."
  }
}

run "rejects_a_non_kms_key" {
  command = plan

  variables {
    kms_key_arn = "alias/aws/states"
  }

  expect_failures = [var.kms_key_arn]
}

run "rejects_an_unsupported_type" {
  command = plan

  variables {
    type = "PIPELINE"
  }

  expect_failures = [var.type]
}

run "rejects_an_empty_definition" {
  command = plan

  variables {
    definition = {}
  }

  expect_failures = [var.definition]
}

run "rejects_an_unsupported_logging_level" {
  command = plan

  variables {
    logging_configuration = {
      level = "DEBUG"
    }
  }

  expect_failures = [var.logging_configuration]
}

run "rejects_a_wildcard_allow_action_in_iam_policies" {
  command = plan

  variables {
    iam_policies = [
      {
        actions   = ["*"]
        resources = ["arn:aws:lambda:eu-west-2:123456789012:function:test-order-processor"]
      }
    ]
  }

  expect_failures = [var.iam_policies]
}

run "disabled_creates_nothing" {
  command = plan

  variables {
    enabled              = false
    events_role_enabled  = true
    logging_configuration = {
      level = "ALL"
    }
  }

  assert {
    condition     = length(aws_sfn_state_machine.this) == 0 && length(aws_iam_role.this) == 0 && length(aws_cloudwatch_log_group.this) == 0 && length(aws_iam_role.events) == 0
    error_message = "enabled = false must create nothing, even with events_role_enabled and a logging level set."
  }

  assert {
    condition     = output.state_machine_arn == null && output.role_arn == null && output.log_group_name == null && output.events_role_arn == null
    error_message = "Outputs are null when disabled."
  }
}
