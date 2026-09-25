# Offline tests: the real AWS provider with dummy credentials, as in
# kms/tests. aws_iam_policy_document is computed locally, so the queue policy
# can be asserted; a mock provider would return a random string for it. Every
# check that would call AWS is skipped and caller identity is overridden, so
# nothing reaches AWS (all runs are plans).
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
  region      = "eu-west-2"
  name        = "orders"
  kms_key_arn = "arn:aws:kms:eu-west-2:123456789012:key/00000000-0000-0000-0000-000000000000"
  tags = {
    Environment = "test"
    Tenant      = "fnx"
    ManagedBy   = "Terraform"
  }
}

run "defaults_encrypt_with_the_cmk_and_add_nothing_else" {
  command = plan

  assert {
    condition     = aws_sqs_queue.this[0].name == "test-orders" && aws_sqs_queue.this[0].fifo_queue == false
    error_message = "The queue is a standard queue named <Environment>-<name>."
  }

  assert {
    condition     = aws_sqs_queue.this[0].kms_master_key_id == var.kms_key_arn
    error_message = "The queue is encrypted with the given CMK, not SQS-managed SSE."
  }

  assert {
    condition     = aws_sqs_queue.this[0].visibility_timeout_seconds == 30 && aws_sqs_queue.this[0].message_retention_seconds == 345600 && aws_sqs_queue.this[0].kms_data_key_reuse_period_seconds == 300
    error_message = "Defaults are Cloud Posse's (30 s visibility, 4 days retention, 300 s data key reuse)."
  }

  assert {
    condition     = length(aws_sqs_queue.dlq) == 0 && length(aws_sqs_queue_redrive_allow_policy.dlq) == 0
    error_message = "No DLQ or redrive policy unless dlq_enabled."
  }

  assert {
    condition     = length(aws_sqs_queue_policy.this) == 0
    error_message = "No queue policy unless iam_policy is set."
  }
}

run "dlq_is_encrypted_and_wired_both_ways" {
  command = plan

  variables {
    dlq_enabled           = true
    dlq_max_receive_count = 3
  }

  assert {
    condition     = aws_sqs_queue.dlq[0].name == "test-orders-dlq" && aws_sqs_queue.dlq[0].kms_master_key_id == var.kms_key_arn
    error_message = "The DLQ is <Environment>-<name>-dlq, encrypted with the same CMK."
  }

  assert {
    condition     = aws_sqs_queue.dlq[0].message_retention_seconds == 1209600
    error_message = "The DLQ keeps messages 14 days by default, longer than the source queue."
  }

  assert {
    condition     = jsondecode(aws_sqs_queue_redrive_allow_policy.dlq[0].redrive_allow_policy) == { redrivePermission = "byQueue", sourceQueueArns = ["arn:aws:sqs:eu-west-2:123456789012:test-orders"] }
    error_message = "Only this instance's queue may redrive into the DLQ."
  }
}

run "fifo_names_both_queues_with_the_suffix" {
  command = plan

  variables {
    fifo_queue                  = true
    content_based_deduplication = true
    dlq_enabled                 = true
  }

  assert {
    condition     = aws_sqs_queue.this[0].name == "test-orders.fifo" && aws_sqs_queue.dlq[0].name == "test-orders-dlq.fifo" && aws_sqs_queue.dlq[0].fifo_queue
    error_message = "A FIFO queue and its DLQ are both FIFO and end in .fifo."
  }
}

run "queue_policy_lets_eventbridge_send_from_one_rule" {
  command = plan

  variables {
    iam_policy = [{
      statements = [{
        sid     = "AllowEventBridgeRule"
        effect  = "Allow"
        actions = ["sqs:SendMessage"]
        principals = [{
          type        = "Service"
          identifiers = ["events.amazonaws.com"]
        }]
        conditions = [{
          test     = "ArnEquals"
          variable = "aws:SourceArn"
          values   = ["arn:aws:events:eu-west-2:123456789012:rule/test-bus/test-orders"]
        }]
      }]
    }]
  }

  assert {
    condition     = one(jsondecode(data.aws_iam_policy_document.queue[0].json).Statement).Resource == "arn:aws:sqs:eu-west-2:123456789012:test-orders"
    error_message = "Statements are scoped to this queue's ARN."
  }

  assert {
    condition     = one(jsondecode(data.aws_iam_policy_document.queue[0].json).Statement).Principal.Service == "events.amazonaws.com"
    error_message = "The principal is passed through."
  }

  assert {
    condition = one(jsondecode(data.aws_iam_policy_document.queue[0].json).Statement).Condition == {
      ArnEquals    = { "aws:SourceArn" = "arn:aws:events:eu-west-2:123456789012:rule/test-bus/test-orders" }
      StringEquals = { "aws:SourceAccount" = "123456789012" }
    }
    error_message = "The caller's aws:SourceArn condition is kept, iam_policy_limit_to_current_account (default true) adds aws:SourceAccount, and nothing else is added."
  }

  assert {
    condition     = length(aws_sqs_queue_policy.this) == 1
    error_message = "The policy is attached to the queue."
  }
}

run "account_limit_can_be_turned_off" {
  command = plan

  variables {
    iam_policy_limit_to_current_account = false
    iam_policy = [{
      statements = [{
        actions    = ["sqs:ReceiveMessage", "sqs:DeleteMessage"]
        principals = [{ type = "AWS", identifiers = ["arn:aws:iam::123456789012:role/consumer"] }]
      }]
    }]
  }

  assert {
    condition     = !can(one(jsondecode(data.aws_iam_policy_document.queue[0].json).Statement).Condition)
    error_message = "Without the account limit no condition is added."
  }
}

run "disabled_creates_nothing" {
  command = plan

  variables {
    enabled     = false
    dlq_enabled = true
  }

  assert {
    condition     = length(aws_sqs_queue.this) == 0 && length(aws_sqs_queue.dlq) == 0
    error_message = "enabled = false must create nothing."
  }

  assert {
    condition     = output.queue_arn == null && output.dead_letter_queue_arn == null
    error_message = "Outputs are null when disabled."
  }
}

run "rejects_a_non_kms_key" {
  command = plan

  variables {
    kms_key_arn = "alias/aws/sqs"
  }

  expect_failures = [var.kms_key_arn]
}

run "rejects_wildcard_actions" {
  command = plan

  variables {
    iam_policy = [{
      statements = [{
        actions    = ["sqs:*"]
        principals = [{ type = "Service", identifiers = ["sns.amazonaws.com"] }]
      }]
    }]
  }

  expect_failures = [var.iam_policy]
}

run "account_limit_leaves_deny_statements_alone" {
  command = plan

  variables {
    iam_policy = [{
      statements = [
        {
          sid        = "AllowSNS"
          actions    = ["sqs:SendMessage"]
          principals = [{ type = "Service", identifiers = ["sns.amazonaws.com"] }]
        },
        {
          sid        = "DenyInsecureTransport"
          effect     = "Deny"
          actions    = ["sqs:*"]
          principals = [{ type = "AWS", identifiers = ["*"] }]
          conditions = [{ test = "Bool", variable = "aws:SecureTransport", values = ["false"] }]
        },
      ]
    }]
  }

  assert {
    condition     = one([for s in jsondecode(data.aws_iam_policy_document.queue[0].json).Statement : s if s.Sid == "AllowSNS"]).Condition == { StringEquals = { "aws:SourceAccount" = "123456789012" } }
    error_message = "Allow statements get aws:SourceAccount."
  }

  assert {
    condition     = one([for s in jsondecode(data.aws_iam_policy_document.queue[0].json).Statement : s if s.Sid == "DenyInsecureTransport"]).Condition == { Bool = { "aws:SecureTransport" = "false" } }
    error_message = "Deny statements are not narrowed by aws:SourceAccount."
  }
}

run "existing_source_account_condition_is_not_duplicated" {
  command = plan

  variables {
    iam_policy = [{
      statements = [{
        actions    = ["sqs:SendMessage"]
        principals = [{ type = "Service", identifiers = ["sns.amazonaws.com"] }]
        conditions = [{ test = "StringEquals", variable = "aws:SourceAccount", values = ["210987654321"] }]
      }]
    }]
  }

  assert {
    condition     = one(jsondecode(data.aws_iam_policy_document.queue[0].json).Statement).Condition == { StringEquals = { "aws:SourceAccount" = "210987654321" } }
    error_message = "A statement that sets aws:SourceAccount itself keeps its own value and gets no second one."
  }
}

run "deny_with_only_not_actions_is_allowed" {
  command = plan

  variables {
    iam_policy = [{
      statements = [{
        sid         = "DenyAllButSend"
        effect      = "Deny"
        not_actions = ["sqs:SendMessage"]
        principals  = [{ type = "Service", identifiers = ["sns.amazonaws.com"] }]
      }]
    }]
  }

  assert {
    condition     = one(jsondecode(data.aws_iam_policy_document.queue[0].json).Statement).NotAction == "sqs:SendMessage" && !can(one(jsondecode(data.aws_iam_policy_document.queue[0].json).Statement).Condition)
    error_message = "A Deny may use not_actions alone, and is not narrowed by aws:SourceAccount."
  }
}

run "rejects_an_allow_without_principals" {
  command = plan

  variables {
    iam_policy = [{
      statements = [{
        actions = ["sqs:SendMessage"]
      }]
    }]
  }

  expect_failures = [var.iam_policy]
}

run "rejects_a_public_allow" {
  command = plan

  variables {
    iam_policy = [{
      statements = [{
        actions    = ["sqs:SendMessage"]
        principals = [{ type = "AWS", identifiers = ["*"] }]
      }]
    }]
  }

  expect_failures = [var.iam_policy]
}

run "rejects_not_principals_on_an_allow" {
  command = plan

  variables {
    iam_policy = [{
      statements = [{
        actions        = ["sqs:SendMessage"]
        not_principals = [{ type = "AWS", identifiers = ["arn:aws:iam::123456789012:root"] }]
      }]
    }]
  }

  expect_failures = [var.iam_policy]
}

run "rejects_statement_resources" {
  command = plan

  variables {
    iam_policy = [{
      statements = [{
        actions    = ["sqs:SendMessage"]
        resources  = ["arn:aws:sqs:eu-west-2:123456789012:other"]
        principals = [{ type = "Service", identifiers = ["sns.amazonaws.com"] }]
      }]
    }]
  }

  expect_failures = [var.iam_policy]
}

run "rejects_fifo_options_on_a_standard_queue" {
  command = plan

  variables {
    content_based_deduplication = true
    fifo_throughput_limit       = "perMessageGroupId"
  }

  expect_failures = [var.content_based_deduplication, var.fifo_throughput_limit]
}

run "rejects_an_out_of_range_retention" {
  command = plan

  variables {
    message_retention_seconds = 1209601
  }

  expect_failures = [var.message_retention_seconds]
}

run "rejects_a_queue_name_over_80_characters" {
  command = plan

  variables {
    # 79 characters for the queue, 83 for its DLQ.
    name        = "a-very-long-queue-name-that-is-fine-alone-not-with-a-suffix"
    dlq_enabled = true
    tags = {
      Environment = "an-environment-name"
      ManagedBy   = "Terraform"
    }
  }

  expect_failures = [aws_sqs_queue.dlq[0]]
}

# --- caller pinning --------------------------------------------------------

run "rejects_a_principal_arn_with_a_wildcard" {
  command = plan

  variables {
    iam_policy = [{
      statements = [{
        actions    = ["sqs:SendMessage"]
        principals = [{ type = "AWS", identifiers = ["arn:aws:iam::*:root"] }]
      }]
    }]
  }

  expect_failures = [var.iam_policy]
}

run "service_allow_pinned_by_source_arn_needs_no_account_limit" {
  command = plan

  variables {
    iam_policy_limit_to_current_account = false
    iam_policy = [{
      statements = [{
        actions    = ["sqs:SendMessage"]
        principals = [{ type = "Service", identifiers = ["events.amazonaws.com"] }]
        conditions = [{ test = "ArnLike", variable = "AWS:SourceArn", values = ["arn:aws:events:eu-west-2:123456789012:rule/test-bus/test-rule"] }]
      }]
    }]
  }

  assert {
    condition     = length(aws_sqs_queue_policy.this) == 1
    error_message = "A service Allow pinned by aws:SourceArn (any case, any positive operator) is accepted without the account limit."
  }
}

run "rejects_an_unpinned_service_allow_without_the_account_limit" {
  command = plan

  variables {
    iam_policy_limit_to_current_account = false
    iam_policy = [{
      statements = [{
        actions    = ["sqs:SendMessage"]
        principals = [{ type = "Service", identifiers = ["sns.amazonaws.com"] }]
        conditions = [{ test = "Bool", variable = "aws:SecureTransport", values = ["true"] }]
      }]
    }]
  }

  expect_failures = [var.iam_policy]
}

run "rejects_a_service_allow_whose_own_source_account_is_negated" {
  command = plan

  variables {
    # The account limit is on, but a statement with its own aws:SourceAccount
    # does not get it, so the negated condition would be all it has.
    iam_policy = [{
      statements = [{
        actions    = ["sqs:SendMessage"]
        principals = [{ type = "Service", identifiers = ["sns.amazonaws.com"] }]
        conditions = [{ test = "StringNotEquals", variable = "aws:SourceAccount", values = ["210987654321"] }]
      }]
    }]
  }

  expect_failures = [var.iam_policy]
}

run "rejects_a_service_allow_pinned_only_if_the_key_exists" {
  command = plan

  variables {
    iam_policy_limit_to_current_account = false
    iam_policy = [{
      statements = [{
        actions    = ["sqs:SendMessage"]
        principals = [{ type = "Service", identifiers = ["sns.amazonaws.com"] }]
        conditions = [{ test = "ArnEqualsIfExists", variable = "aws:SourceArn", values = ["arn:aws:sns:eu-west-2:123456789012:test-topic"] }]
      }]
    }]
  }

  expect_failures = [var.iam_policy]
}

run "rejects_a_service_allow_pinned_to_a_wildcard" {
  command = plan

  variables {
    iam_policy_limit_to_current_account = false
    iam_policy = [{
      statements = [{
        actions    = ["sqs:SendMessage"]
        principals = [{ type = "Service", identifiers = ["sns.amazonaws.com"] }]
        conditions = [{ test = "StringLike", variable = "aws:SourceAccount", values = ["*"] }]
      }]
    }]
  }

  expect_failures = [var.iam_policy]
}
