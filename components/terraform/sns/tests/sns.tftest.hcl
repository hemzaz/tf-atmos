# Offline tests: the real AWS provider with dummy credentials, as in
# kms/tests. aws_iam_policy_document is computed locally, so the topic policy
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
  name        = "alerts"
  kms_key_arn = "arn:aws:kms:eu-west-2:123456789012:key/00000000-0000-0000-0000-000000000000"
  tags = {
    Environment = "test"
    Tenant      = "fnx"
    ManagedBy   = "Terraform"
  }
}

run "defaults_encrypt_with_the_cmk_and_deny_plain_http" {
  command = plan

  assert {
    condition     = aws_sns_topic.this[0].name == "test-alerts" && aws_sns_topic.this[0].fifo_topic == false
    error_message = "The topic is a standard topic named <Environment>-<name>."
  }

  assert {
    condition     = aws_sns_topic.this[0].kms_master_key_id == var.kms_key_arn
    error_message = "The topic is encrypted with the given CMK."
  }

  assert {
    condition     = length(aws_sns_topic_policy.this) == 1 && length(jsondecode(data.aws_iam_policy_document.topic[0].json).Statement) == 1
    error_message = "Without publishers the policy has only the TLS statement."
  }

  assert {
    condition     = one(jsondecode(data.aws_iam_policy_document.topic[0].json).Statement).Effect == "Deny" && one(jsondecode(data.aws_iam_policy_document.topic[0].json).Statement).Condition.Bool["aws:SecureTransport"] == "false"
    error_message = "Publishing without TLS is denied."
  }

  assert {
    condition     = one(jsondecode(data.aws_iam_policy_document.topic[0].json).Statement).Resource == "arn:aws:sns:eu-west-2:123456789012:test-alerts"
    error_message = "The policy is scoped to this topic."
  }

  assert {
    condition     = length(aws_sns_topic_subscription.this) == 0
    error_message = "No subscriptions by default."
  }
}

run "services_publish_only_from_this_account" {
  command = plan

  variables {
    allowed_aws_services_for_sns_published = ["events.amazonaws.com", "cloudwatch.amazonaws.com"]
    allowed_iam_arns_for_sns_publish       = ["arn:aws:iam::210987654321:role/publisher"]
  }

  assert {
    condition     = toset(one([for s in jsondecode(data.aws_iam_policy_document.topic[0].json).Statement : s if s.Sid == "AllowServicesToPublish"]).Principal.Service) == toset(["events.amazonaws.com", "cloudwatch.amazonaws.com"])
    error_message = "The listed services may publish."
  }

  assert {
    condition     = one([for s in jsondecode(data.aws_iam_policy_document.topic[0].json).Statement : s if s.Sid == "AllowServicesToPublish"]).Condition.StringEquals["aws:SourceAccount"] == "123456789012"
    error_message = "Service publishing is limited to this account (aws:SourceAccount)."
  }

  assert {
    condition     = one([for s in jsondecode(data.aws_iam_policy_document.topic[0].json).Statement : s if s.Sid == "AllowPrincipalsToPublish"]).Principal.AWS == "arn:aws:iam::210987654321:role/publisher"
    error_message = "The listed IAM ARNs may publish."
  }

  assert {
    condition     = one([for s in jsondecode(data.aws_iam_policy_document.topic[0].json).Statement : s if s.Sid == "AllowServicesToPublish"]).Action == "sns:Publish"
    error_message = "Publishers get sns:Publish only."
  }
}

run "subscriptions_with_a_dead_letter_queue" {
  command = plan

  variables {
    subscribers = {
      orders = {
        protocol              = "sqs"
        endpoint              = "arn:aws:sqs:eu-west-2:123456789012:test-orders"
        raw_message_delivery  = true
        dead_letter_queue_arn = "arn:aws:sqs:eu-west-2:123456789012:test-alerts-dlq"
      }
      oncall = {
        protocol = "https"
        endpoint = "https://events.example.com/sns"
      }
    }
  }

  assert {
    condition     = aws_sns_topic_subscription.this["orders"].protocol == "sqs" && aws_sns_topic_subscription.this["orders"].raw_message_delivery
    error_message = "Subscriber settings are passed through."
  }

  assert {
    condition     = jsondecode(aws_sns_topic_subscription.this["orders"].redrive_policy) == { deadLetterTargetArn = "arn:aws:sqs:eu-west-2:123456789012:test-alerts-dlq" }
    error_message = "dead_letter_queue_arn becomes the subscription's redrive policy."
  }

  assert {
    condition     = aws_sns_topic_subscription.this["oncall"].endpoint == "https://events.example.com/sns"
    error_message = "Every subscriber gets a subscription."
  }
}

run "fifo_topic" {
  command = plan

  variables {
    fifo_topic                  = true
    content_based_deduplication = true
  }

  assert {
    condition     = aws_sns_topic.this[0].name == "test-alerts.fifo" && aws_sns_topic.this[0].fifo_topic && aws_sns_topic.this[0].display_name == "test-alerts"
    error_message = "A FIFO topic ends in .fifo; the display name has no dot."
  }
}

run "policy_json_is_merged_and_the_tls_deny_survives" {
  command = plan

  variables {
    sns_topic_policy_json = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Sid       = "AllowOrgPublish"
          Effect    = "Allow"
          Principal = { AWS = "*" }
          Action    = "sns:Publish"
          Resource  = "arn:aws:sns:eu-west-2:123456789012:test-alerts"
          Condition = { StringEquals = { "aws:PrincipalOrgID" = "o-example" } }
        },
        {
          # Tries to replace the TLS deny with a no-op; the generated one wins.
          Sid       = "DenyInsecureTransport"
          Effect    = "Deny"
          Principal = { AWS = "*" }
          Action    = "sns:Publish"
          Resource  = "arn:aws:sns:eu-west-2:123456789012:test-alerts"
          Condition = { Bool = { "aws:SecureTransport" = "true" } }
        },
      ]
    })
  }

  assert {
    condition     = toset([for s in jsondecode(data.aws_iam_policy_document.topic[0].json).Statement : s.Sid]) == toset(["AllowOrgPublish", "DenyInsecureTransport"])
    error_message = "The caller's statements are merged into the generated policy."
  }

  assert {
    condition     = one([for s in jsondecode(data.aws_iam_policy_document.topic[0].json).Statement : s if s.Sid == "DenyInsecureTransport"]).Condition.Bool["aws:SecureTransport"] == "false"
    error_message = "The generated TLS deny wins over a caller statement with the same Sid."
  }
}

run "rejects_an_unconditioned_public_allow_in_policy_json" {
  command = plan

  variables {
    sns_topic_policy_json = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect    = "Allow"
        Principal = "*"
        Action    = "sns:Publish"
        Resource  = "*"
      }]
    })
  }

  expect_failures = [var.sns_topic_policy_json]
}

run "rejects_an_unconditioned_aws_star_allow_in_policy_json" {
  command = plan

  variables {
    sns_topic_policy_json = jsonencode({
      Version   = "2012-10-17"
      Statement = { Effect = "Allow", Principal = { AWS = ["*"] }, Action = "sns:Subscribe", Resource = "*" }
    })
  }

  expect_failures = [var.sns_topic_policy_json]
}

run "rejects_not_principal_on_an_allow_in_policy_json" {
  command = plan

  variables {
    sns_topic_policy_json = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect       = "Allow"
        NotPrincipal = { AWS = "arn:aws:iam::123456789012:root" }
        Action       = "sns:Publish"
        Resource     = "arn:aws:sns:eu-west-2:123456789012:test-alerts"
      }]
    })
  }

  expect_failures = [var.sns_topic_policy_json]
}

run "rejects_a_public_allow_with_an_empty_condition_in_policy_json" {
  command = plan

  variables {
    sns_topic_policy_json = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect    = "Allow"
        Principal = { AWS = "*" }
        Action    = "sns:Publish"
        Resource  = "arn:aws:sns:eu-west-2:123456789012:test-alerts"
        Condition = {}
      }]
    })
  }

  expect_failures = [var.sns_topic_policy_json]
}

run "rejects_a_wildcard_principal_arn_in_policy_json" {
  command = plan

  variables {
    sns_topic_policy_json = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect    = "Allow"
        Principal = { AWS = ["arn:aws:iam::*:root"] }
        Action    = "sns:Publish"
        Resource  = "arn:aws:sns:eu-west-2:123456789012:test-alerts"
        Condition = { StringEquals = { "aws:PrincipalOrgID" = "o-example" } }
      }]
    })
  }

  expect_failures = [var.sns_topic_policy_json]
}

run "disabled_creates_nothing" {
  command = plan

  variables {
    enabled     = false
    subscribers = { q = { protocol = "sqs", endpoint = "arn:aws:sqs:eu-west-2:123456789012:q" } }
  }

  assert {
    condition     = length(aws_sns_topic.this) == 0 && length(aws_sns_topic_subscription.this) == 0 && length(aws_sns_topic_policy.this) == 0
    error_message = "enabled = false must create nothing."
  }

  assert {
    condition     = output.sns_topic_arn == null && output.sns_topic_subscriptions == {}
    error_message = "Outputs are null or empty when disabled."
  }
}

run "rejects_a_non_kms_key" {
  command = plan

  variables {
    kms_key_arn = "alias/aws/sns"
  }

  expect_failures = [var.kms_key_arn]
}

run "rejects_plain_http_and_firehose_without_a_role" {
  command = plan

  variables {
    subscribers = {
      web  = { protocol = "http", endpoint = "http://example.com" }
      hose = { protocol = "firehose", endpoint = "arn:aws:firehose:eu-west-2:123456789012:deliverystream/x" }
    }
  }

  expect_failures = [var.subscribers]
}

run "rejects_a_non_service_publisher" {
  command = plan

  variables {
    allowed_aws_services_for_sns_published = ["*"]
  }

  expect_failures = [var.allowed_aws_services_for_sns_published]
}

run "rejects_deduplication_on_a_standard_topic" {
  command = plan

  variables {
    content_based_deduplication = true
  }

  expect_failures = [var.content_based_deduplication]
}
