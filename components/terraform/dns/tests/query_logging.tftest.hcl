# Mock-provider tests for Route53 public query logging (query-logging.tf): no
# AWS credentials, no network. Run from the component directory with
# `terraform init -backend=false && terraform test`.
#
# Route53 only publishes to a us-east-1 log group, after a us-east-1 CloudWatch
# Logs resource policy lets route53.amazonaws.com write to it; a CMK on that
# group must be in us-east-1 and let logs.us-east-1 use it. override_during =
# plan makes the mocked ARNs and account ids known at plan, so the policy
# documents can be decoded and asserted.

mock_provider "aws" {
  override_during = plan

  mock_resource "aws_route53_zone" {
    defaults = {
      zone_id = "ZMAIN000000000000000"
      arn     = "arn:aws:route53:::hostedzone/ZMAIN000000000000000"
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:us-east-1:111111111111:log-group:/aws/route53/fnx.example.com/queries"
    }
  }

  mock_resource "aws_kms_key" {
    defaults = {
      arn    = "arn:aws:kms:us-east-1:111111111111:key/11111111-1111-1111-1111-111111111111"
      key_id = "11111111-1111-1111-1111-111111111111"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "111111111111"
    }
  }
}

mock_provider "aws" {
  alias           = "dns_account"
  override_during = plan

  mock_resource "aws_route53_zone" {
    defaults = {
      zone_id = "ZDNSACCT000000000000"
      arn     = "arn:aws:route53:::hostedzone/ZDNSACCT000000000000"
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:us-east-1:222222222222:log-group:/aws/route53/fnx.example.com/queries"
    }
  }

  mock_resource "aws_kms_key" {
    defaults = {
      arn    = "arn:aws:kms:us-east-1:222222222222:key/22222222-2222-2222-2222-222222222222"
      key_id = "22222222-2222-2222-2222-222222222222"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "222222222222"
    }
  }
}

variables {
  region      = "eu-west-2"
  root_domain = "fnx.example.com"
  tags = {
    Environment = "test"
  }
}

run "public_zone_logs_to_us_east_1" {
  command = plan

  variables {
    zones = {
      main     = { name = "fnx.example.com", enable_query_logging = true }
      internal = { name = "internal.fnx.example.com", vpc_associations = ["vpc-0123456789abcdef0"] }
      services = { name = "services.fnx.example.com" }
    }
  }

  assert {
    condition = (
      keys(aws_cloudwatch_log_group.dns_query_logs) == ["main"]
      && keys(aws_route53_query_log.query_logging) == ["main"]
      && length(aws_cloudwatch_log_group.dns_account_query_logs) == 0
      && length(aws_route53_query_log.dns_account_query_logging) == 0
    )
    error_message = "Only the query-logged public zone gets a log group and a query log config; the private zone and the unlogged zone get none."
  }

  assert {
    condition = (
      aws_cloudwatch_log_group.dns_query_logs["main"].region == "us-east-1"
      && aws_cloudwatch_log_group.dns_query_logs["main"].name == "/aws/route53/fnx.example.com/queries"
      && aws_cloudwatch_log_group.dns_query_logs["main"].retention_in_days == 7
      && aws_cloudwatch_log_group.dns_query_logs["main"].kms_key_id == aws_kms_key.query_logs[0].arn
    )
    error_message = "The log group is in us-east-1 (not the stack's eu-west-2), under /aws/route53/, kept 7 days by default and encrypted with the component's own key."
  }

  assert {
    condition = (
      aws_route53_query_log.query_logging["main"].cloudwatch_log_group_arn == aws_cloudwatch_log_group.dns_query_logs["main"].arn
      && aws_route53_query_log.query_logging["main"].zone_id == "ZMAIN000000000000000"
    )
    error_message = "The query log config points the zone at its own log group."
  }

  # KMS key: us-east-1, rotation on, account root plus logs.us-east-1 scoped by
  # the log group encryption context.
  assert {
    condition = (
      aws_kms_key.query_logs[0].region == "us-east-1"
      && aws_kms_key.query_logs[0].enable_key_rotation == true
      && aws_kms_alias.query_logs[0].region == "us-east-1"
      && aws_kms_alias.query_logs[0].name == "alias/route53-query-logs-fnx-example-com"
    )
    error_message = "The query log key and its alias are in us-east-1, with rotation on."
  }

  assert {
    condition = (
      one([for s in jsondecode(aws_kms_key.query_logs[0].policy).Statement : s.Principal.AWS if s.Sid == "EnableAccountAdministration"]) == "arn:aws:iam::111111111111:root"
      && one([for s in jsondecode(aws_kms_key.query_logs[0].policy).Statement : s.Principal.Service if s.Sid == "AllowCloudWatchLogsRoute53QueryLogGroups"]) == "logs.us-east-1.amazonaws.com"
      && one([for s in jsondecode(aws_kms_key.query_logs[0].policy).Statement : s.Condition.ArnLike["kms:EncryptionContext:aws:logs:arn"] if s.Sid == "AllowCloudWatchLogsRoute53QueryLogGroups"]) == "arn:aws:logs:us-east-1:111111111111:log-group:/aws/route53/*"
    )
    error_message = "The key policy grants the account root and logs.us-east-1.amazonaws.com, the latter only for this account's /aws/route53/* log groups in us-east-1 (kms:EncryptionContext:aws:logs:arn)."
  }

  # Resource policy: us-east-1, route53.amazonaws.com, this zone and account only.
  assert {
    condition = (
      aws_cloudwatch_log_resource_policy.route53_query_logging[0].region == "us-east-1"
      && aws_cloudwatch_log_resource_policy.route53_query_logging[0].policy_name == "route53-query-logging-fnx-example-com"
      && length(aws_cloudwatch_log_resource_policy.dns_account_route53_query_logging) == 0
    )
    error_message = "One resource policy, in us-east-1, named after the instance's first query-logged zone."
  }

  assert {
    condition = (
      jsondecode(aws_cloudwatch_log_resource_policy.route53_query_logging[0].policy_document).Statement[0].Principal.Service == "route53.amazonaws.com"
      && toset(jsondecode(aws_cloudwatch_log_resource_policy.route53_query_logging[0].policy_document).Statement[0].Action) == toset(["logs:CreateLogStream", "logs:PutLogEvents"])
      && jsondecode(aws_cloudwatch_log_resource_policy.route53_query_logging[0].policy_document).Statement[0].Resource == ["arn:aws:logs:us-east-1:111111111111:log-group:/aws/route53/fnx.example.com/queries:*"]
      && jsondecode(aws_cloudwatch_log_resource_policy.route53_query_logging[0].policy_document).Statement[0].Condition.StringEquals["aws:SourceAccount"] == "111111111111"
      && jsondecode(aws_cloudwatch_log_resource_policy.route53_query_logging[0].policy_document).Statement[0].Condition.ArnLike["aws:SourceArn"] == ["arn:aws:route53:::hostedzone/ZMAIN000000000000000"]
    )
    error_message = "The resource policy lets route53.amazonaws.com CreateLogStream/PutLogEvents on this instance's log group only, for this account (aws:SourceAccount) and this hosted zone (aws:SourceArn)."
  }
}

run "retention_and_caller_key_overrides" {
  command = plan

  variables {
    query_log_retention_in_days = 90
    zones = {
      main = { name = "fnx.example.com", enable_query_logging = true }
      services = {
        name                 = "services.fnx.example.com"
        enable_query_logging = true
        query_logging_config = {
          retention_days = "30"
          kms_key_id     = "arn:aws:kms:us-east-1:111111111111:key/33333333-3333-3333-3333-333333333333"
        }
      }
    }
  }

  assert {
    condition = (
      aws_cloudwatch_log_group.dns_query_logs["main"].retention_in_days == 90
      && aws_cloudwatch_log_group.dns_query_logs["services"].retention_in_days == 30
      && aws_cloudwatch_log_group.dns_query_logs["services"].kms_key_id == "arn:aws:kms:us-east-1:111111111111:key/33333333-3333-3333-3333-333333333333"
      && aws_cloudwatch_log_group.dns_query_logs["main"].kms_key_id == aws_kms_key.query_logs[0].arn
    )
    error_message = "query_log_retention_in_days is the default retention; a zone's query_logging_config overrides retention and key."
  }

  assert {
    condition = (
      length(aws_cloudwatch_log_resource_policy.route53_query_logging) == 1
      && length(jsondecode(aws_cloudwatch_log_resource_policy.route53_query_logging[0].policy_document).Statement[0].Resource) == 2
    )
    error_message = "One resource policy covers both of the instance's log groups."
  }
}

run "caller_key_only_creates_no_key" {
  command = plan

  variables {
    zones = {
      main = {
        name                 = "fnx.example.com"
        enable_query_logging = true
        query_logging_config = { kms_key_id = "arn:aws:kms:us-east-1:111111111111:key/33333333-3333-3333-3333-333333333333" }
      }
    }
  }

  assert {
    condition     = length(aws_kms_key.query_logs) == 0 && length(aws_kms_alias.query_logs) == 0
    error_message = "With every log group on a caller key, the component creates no key."
  }
}

run "no_query_logging_creates_nothing" {
  command = plan

  variables {
    zones = {
      main     = { name = "fnx.example.com" }
      internal = { name = "internal.fnx.example.com", vpc_associations = ["vpc-0123456789abcdef0"] }
    }
  }

  assert {
    condition = (
      length(aws_cloudwatch_log_group.dns_query_logs) == 0
      && length(aws_route53_query_log.query_logging) == 0
      && length(aws_kms_key.query_logs) == 0
      && length(aws_cloudwatch_log_resource_policy.route53_query_logging) == 0
      && length(data.aws_caller_identity.dns_account) == 0
    )
    error_message = "Without enable_query_logging (the sandbox case) there is no log group, key, resource policy or query log config."
  }
}

run "dns_account_zones_log_in_the_dns_account" {
  command = plan

  variables {
    multi_account_dns_delegation = true
    zones = {
      main = { name = "fnx.example.com", enable_query_logging = true }
    }
  }

  assert {
    condition = (
      length(aws_cloudwatch_log_group.dns_query_logs) == 0
      && length(aws_cloudwatch_log_resource_policy.route53_query_logging) == 0
      && length(aws_kms_key.query_logs) == 0
      && aws_cloudwatch_log_group.dns_account_query_logs["main"].region == "us-east-1"
      && aws_cloudwatch_log_group.dns_account_query_logs["main"].kms_key_id == aws_kms_key.dns_account_query_logs[0].arn
      && aws_kms_key.dns_account_query_logs[0].region == "us-east-1"
      && aws_cloudwatch_log_resource_policy.dns_account_route53_query_logging[0].region == "us-east-1"
    )
    error_message = "A DNS-account zone's log group, key and resource policy are created in the DNS account, in us-east-1."
  }

  assert {
    condition = (
      jsondecode(aws_cloudwatch_log_resource_policy.dns_account_route53_query_logging[0].policy_document).Statement[0].Condition.StringEquals["aws:SourceAccount"] == "222222222222"
      && jsondecode(aws_cloudwatch_log_resource_policy.dns_account_route53_query_logging[0].policy_document).Statement[0].Condition.ArnLike["aws:SourceArn"] == ["arn:aws:route53:::hostedzone/ZDNSACCT000000000000"]
      && one([for s in jsondecode(aws_kms_key.dns_account_query_logs[0].policy).Statement : s.Condition.ArnLike["kms:EncryptionContext:aws:logs:arn"] if s.Sid == "AllowCloudWatchLogsRoute53QueryLogGroups"]) == "arn:aws:logs:us-east-1:222222222222:log-group:/aws/route53/*"
      && aws_route53_query_log.dns_account_query_logging["main"].zone_id == "ZDNSACCT000000000000"
    )
    error_message = "The DNS-account policy and key name the DNS account, not the main one."
  }
}

run "private_zone_query_logging_rejected" {
  command = plan

  variables {
    zones = {
      internal = { name = "internal.fnx.example.com", enable_query_logging = true, vpc_associations = ["vpc-0123456789abcdef0"] }
    }
  }

  expect_failures = [var.zones]
}

run "caller_log_group_must_be_in_us_east_1" {
  command = plan

  variables {
    zones = {
      main = {
        name                 = "fnx.example.com"
        enable_query_logging = true
        query_logging_config = { cloudwatch_log_group_arn = "arn:aws:logs:eu-west-2:111111111111:log-group:/aws/route53/fnx.example.com" }
      }
    }
  }

  expect_failures = [var.zones]
}

run "caller_key_must_be_in_us_east_1" {
  command = plan

  variables {
    zones = {
      main = {
        name                 = "fnx.example.com"
        enable_query_logging = true
        query_logging_config = { kms_key_id = "arn:aws:kms:eu-west-2:111111111111:key/33333333-3333-3333-3333-333333333333" }
      }
    }
  }

  expect_failures = [var.zones]
}

run "query_log_retention_must_be_a_cloudwatch_value" {
  command = plan

  variables {
    query_log_retention_in_days = 10
    zones = {
      main = { name = "fnx.example.com", enable_query_logging = true }
    }
  }

  expect_failures = [var.query_log_retention_in_days]
}

# The name suffix is derived from the first zone by default, so a zone that
# sorts earlier renames it; query_logging_name pins it.
run "derived_name_changes_with_an_earlier_zone" {
  command = plan

  variables {
    zones = {
      main  = { name = "fnx.example.com", enable_query_logging = true }
      early = { name = "a.fnx.example.com", enable_query_logging = true }
    }
  }

  assert {
    condition     = aws_cloudwatch_log_resource_policy.route53_query_logging[0].policy_name == "route53-query-logging-a-fnx-example-com"
    error_message = "Without query_logging_name the suffix follows the alphabetically first logged zone."
  }
}

run "query_logging_name_is_stable_when_an_earlier_zone_is_added" {
  command = plan

  variables {
    query_logging_name = "fnx-example-com"
    zones = {
      main  = { name = "fnx.example.com", enable_query_logging = true }
      early = { name = "a.fnx.example.com", enable_query_logging = true }
    }
  }

  assert {
    condition = (
      aws_cloudwatch_log_resource_policy.route53_query_logging[0].policy_name == "route53-query-logging-fnx-example-com"
      && aws_kms_alias.query_logs[0].name == "alias/route53-query-logs-fnx-example-com"
    )
    error_message = "With query_logging_name set, adding a zone that sorts earlier must not change the policy name or the key alias."
  }
}

run "query_logging_name_must_be_a_valid_suffix" {
  command = plan

  variables {
    query_logging_name = "Bad Name"
    zones = {
      main = { name = "fnx.example.com", enable_query_logging = true }
    }
  }

  expect_failures = [var.query_logging_name]
}

run "caller_log_group_in_the_zone_account_is_accepted" {
  command = plan

  variables {
    zones = {
      main = {
        name                 = "fnx.example.com"
        enable_query_logging = true
        query_logging_config = { cloudwatch_log_group_arn = "arn:aws:logs:us-east-1:111111111111:log-group:/aws/route53/fnx.example.com" }
      }
    }
  }

  assert {
    condition     = aws_route53_query_log.query_logging["main"].cloudwatch_log_group_arn == "arn:aws:logs:us-east-1:111111111111:log-group:/aws/route53/fnx.example.com"
    error_message = "A caller log group in this account is used as given."
  }
}

run "caller_log_group_must_be_in_the_zone_account" {
  command = plan

  variables {
    zones = {
      main = {
        name                 = "fnx.example.com"
        enable_query_logging = true
        query_logging_config = { cloudwatch_log_group_arn = "arn:aws:logs:us-east-1:999999999999:log-group:/aws/route53/fnx.example.com" }
      }
    }
  }

  expect_failures = [aws_route53_query_log.query_logging["main"]]
}

run "caller_log_group_must_be_in_the_dns_account_for_dns_account_zones" {
  command = plan

  variables {
    multi_account_dns_delegation = true
    zones = {
      main = {
        name                 = "fnx.example.com"
        enable_query_logging = true
        query_logging_config = { cloudwatch_log_group_arn = "arn:aws:logs:us-east-1:111111111111:log-group:/aws/route53/fnx.example.com" }
      }
    }
  }

  expect_failures = [aws_route53_query_log.dns_account_query_logging["main"]]
}
