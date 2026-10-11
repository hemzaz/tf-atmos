# Mock-provider tests for the RDS event subscription on the alarm topic
# (rds_event_subscription_enabled, Cloud Posse's rds-cloudwatch-sns-alarms):
# no AWS credentials, no network. Run from the component directory with
# `terraform init -backend=false && terraform test`.

mock_provider "aws" {}

variables {
  region           = "eu-central-1"
  name             = "main"
  create_sns_topic = true
  rds_instances    = ["ec1-prod-main-db"]
  kms_key_id       = "arn:aws:kms:eu-central-1:123456789012:key/mrk-1234567890abcdef1234567890abcdef"
  tags = {
    Environment = "ec1"
    Tenant      = "fnx"
    ManagedBy   = "Terraform"
  }
}

run "subscribes_the_created_topic_to_the_instances_events" {
  command = plan

  variables {
    rds_event_subscription_enabled = true
    rds_instances                  = ["ue1-prod-data-db", "ue1-prod-data-db-read-replica"]
  }

  override_data {
    target = data.aws_caller_identity.current
    values = { account_id = "123456789012" }
  }

  override_data {
    target = data.aws_partition.current
    values = { partition = "aws" }
  }

  override_resource {
    target          = aws_sns_topic.alarms
    override_during = plan
    values          = { arn = "arn:aws:sns:eu-central-1:123456789012:ec1-main-alarms" }
  }

  assert {
    condition     = length(aws_db_event_subscription.rds) == 1 && aws_db_event_subscription.rds[0].sns_topic == "arn:aws:sns:eu-central-1:123456789012:ec1-main-alarms" && aws_db_event_subscription.rds[0].source_type == "db-instance"
    error_message = "One db-instance event subscription publishes to this component's own topic."
  }

  assert {
    condition     = aws_db_event_subscription.rds[0].name == "ec1-main-rds-events" && toset(aws_db_event_subscription.rds[0].source_ids) == toset(["ue1-prod-data-db", "ue1-prod-data-db-read-replica"])
    error_message = "The subscription is <Environment>-<name>-rds-events and its sources are the rds_instances."
  }

  assert {
    condition     = toset(aws_db_event_subscription.rds[0].event_categories) == toset(["availability", "failover", "failure", "low storage", "maintenance", "notification", "read replica", "recovery"])
    error_message = "The default categories cover availability, failover, failure, storage, maintenance, replica and recovery events."
  }

  assert {
    condition = (
      length(jsondecode(aws_sns_topic_policy.alarms[0].policy).Statement) == 2
      && jsondecode(aws_sns_topic_policy.alarms[0].policy).Statement[0].Principal.Service == "cloudwatch.amazonaws.com"
      && jsondecode(aws_sns_topic_policy.alarms[0].policy).Statement[1] == {
        Sid       = "AllowRdsEventSubscriptionsToPublish"
        Effect    = "Allow"
        Principal = { Service = "events.rds.amazonaws.com" }
        Action    = "SNS:Publish"
        Resource  = "arn:aws:sns:eu-central-1:123456789012:ec1-main-alarms"
        Condition = {
          StringEquals = { "aws:SourceAccount" = "123456789012" }
          ArnLike = { "aws:SourceArn" = [
            "arn:aws:rds:eu-central-1:123456789012:db:ue1-prod-data-db",
            "arn:aws:rds:eu-central-1:123456789012:db:ue1-prod-data-db-read-replica",
          ] }
        }
      }
    )
    error_message = "The topic policy keeps the CloudWatch alarms statement and lets RDS publish for the subscribed instances only (no relay rule statement)."
  }
}

run "event_categories_are_configurable" {
  command = plan

  variables {
    rds_event_subscription_enabled = true
    rds_event_categories           = ["failover", "failure"]
  }

  assert {
    condition     = toset(aws_db_event_subscription.rds[0].event_categories) == toset(["failover", "failure"]) && toset(aws_db_event_subscription.rds[0].source_ids) == toset(["ec1-prod-main-db"])
    error_message = "rds_event_categories replaces the default list."
  }
}

run "off_by_default" {
  command = plan

  assert {
    condition     = length(aws_db_event_subscription.rds) == 0 && length(aws_sns_topic_policy.alarms) == 0
    error_message = "Without rds_event_subscription_enabled there is no subscription and the topic keeps SNS's default policy."
  }
}

run "rejects_an_unknown_event_category" {
  command = plan

  variables {
    rds_event_subscription_enabled = true
    rds_event_categories           = ["outage"]
  }

  expect_failures = [var.rds_event_categories]
}

run "rejects_a_subscription_without_topic" {
  command = plan

  variables {
    rds_event_subscription_enabled = true
    create_sns_topic               = false
  }

  expect_failures = [var.rds_event_subscription_enabled]
}

run "rejects_a_subscription_without_instances" {
  command = plan

  variables {
    rds_event_subscription_enabled = true
    rds_instances                  = []
  }

  expect_failures = [var.rds_event_subscription_enabled]
}
