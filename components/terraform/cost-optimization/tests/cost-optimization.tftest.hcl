# Offline tests: the real AWS provider with dummy credentials plus
# override_data, as in s3/tests. Every IAM policy here is built with
# jsonencode() from variables/locals alone (no data source computes it), so
# it can be asserted directly from the plan. Nothing reaches AWS (all runs
# are plans).
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
  name        = "main"
  environment = "dev"
  kms_key_arn = "arn:aws:kms:eu-west-2:123456789012:key/00000000-0000-0000-0000-000000000000"
  tags = {
    Environment = "test"
    Tenant      = "fnx"
    ManagedBy   = "Terraform"
  }
  monthly_budget_limit            = "1000"
  budget_notification_emails      = ["budget@example.com"]
  cost_anomaly_notification_email = "anomaly@example.com"
  cost_alert_emails               = ["alerts@example.com"]
  cleanup_dry_run                 = "true"
}

run "names_follow_environment_name_convention" {
  command = plan

  assert {
    condition     = aws_lambda_function.scheduler[0].function_name == "test-main-scheduler"
    error_message = "The scheduler function is named <Environment>-<name>-scheduler."
  }

  assert {
    condition     = aws_lambda_function.savings_analyzer.function_name == "test-main-savings-analyzer"
    error_message = "The savings analyzer function is named <Environment>-<name>-savings-analyzer."
  }

  assert {
    condition     = aws_lambda_function.resource_cleanup.function_name == "test-main-resource-cleanup"
    error_message = "The resource cleanup function is named <Environment>-<name>-resource-cleanup."
  }

  assert {
    condition     = aws_sns_topic.cost_alerts.name == "test-main-cost-alerts"
    error_message = "The SNS topic is named <Environment>-<name>-cost-alerts."
  }

  assert {
    condition     = aws_budgets_budget.monthly.name == "test-main-monthly-budget"
    error_message = "The budget is named <Environment>-<name>-monthly-budget."
  }
}

run "scheduler_describe_statement_is_separate_and_unconditioned" {
  command = plan

  assert {
    condition = one([
      for s in jsondecode(aws_iam_role_policy.scheduler[0].policy).Statement : s
      if s.Sid == "DescribeTargets"
    ]) != null
    error_message = "Describe*/List* actions have their own statement (DescribeTargets)."
  }

  assert {
    condition = alltrue([
      for a in one([
        for s in jsondecode(aws_iam_role_policy.scheduler[0].policy).Statement : s
        if s.Sid == "DescribeTargets"
      ]).Action : can(regex("^(ec2:Describe|rds:Describe|rds:ListTagsForResource|eks:Describe|autoscaling:Describe)", a))
    ])
    error_message = "The DescribeTargets statement contains only read-only Describe*/List* actions."
  }

  assert {
    condition = try(one([
      for s in jsondecode(aws_iam_role_policy.scheduler[0].policy).Statement : s
      if s.Sid == "DescribeTargets"
    ]).Condition, null) == null
    error_message = "Describe*/List* actions carry no resource-tag Condition (they have no resource-level permission support)."
  }
}

run "scheduler_mutating_statements_are_never_unconditioned" {
  command = plan

  assert {
    condition = alltrue([
      for s in jsondecode(aws_iam_role_policy.scheduler[0].policy).Statement :
      try(s.Condition, null) != null
      if s.Sid != "DescribeTargets" && s.Sid != "OwnLogGroup"
    ])
    error_message = "Every mutating statement (start/stop/scale) is conditioned on the target resource's tags; none applies to an unconditioned '*'."
  }

  assert {
    condition = one([
      for s in jsondecode(aws_iam_role_policy.scheduler[0].policy).Statement : s
      if s.Sid == "StartStopEC2"
    ]).Condition.StringEquals["ec2:ResourceTag/Environment"] == "test"
    error_message = "EC2 start/stop is conditioned on ec2:ResourceTag/Environment (EC2's own tag-condition namespace)."
  }

  assert {
    condition = one([
      for s in jsondecode(aws_iam_role_policy.scheduler[0].policy).Statement : s
      if s.Sid == "StartStopRDS"
    ]).Condition.StringEquals["aws:ResourceTag/Environment"] == "test"
    error_message = "RDS start/stop is conditioned on aws:ResourceTag/Environment (RDS has no service-specific tag-condition key)."
  }
}

run "scheduler_logs_are_scoped_to_its_own_log_group" {
  command = plan

  assert {
    condition = one([
      for s in jsondecode(aws_iam_role_policy.scheduler[0].policy).Statement : s
      if s.Sid == "OwnLogGroup"
    ]).Resource[0] == "arn:aws:logs:eu-west-2:123456789012:log-group:/aws/lambda/test-main-scheduler:*"
    error_message = "The logs statement is scoped to the scheduler function's own log group, never arn:aws:logs:*:*:*."
  }
}

run "resource_cleanup_describe_and_delete_statements_are_separate" {
  command = plan

  assert {
    condition = alltrue([
      for a in one([
        for s in jsondecode(aws_iam_role_policy.resource_cleanup.policy).Statement : s
        if s.Sid == "DescribeCleanupCandidates"
      ]).Action : can(regex("^ec2:Describe", a))
    ])
    error_message = "DescribeCleanupCandidates contains only Describe* actions."
  }

  assert {
    condition = try(one([
      for s in jsondecode(aws_iam_role_policy.resource_cleanup.policy).Statement : s
      if s.Sid == "DescribeCleanupCandidates"
    ]).Condition, null) == null
    error_message = "Describe* actions carry no Condition."
  }

  assert {
    condition = one([
      for s in jsondecode(aws_iam_role_policy.resource_cleanup.policy).Statement : s
      if s.Sid == "DeleteCleanupCandidates"
    ]).Condition.StringEquals["ec2:ResourceTag/CostOptimization"] == "cleanup-eligible"
    error_message = "Delete actions are conditioned on the opt-in cleanup tag, not just Environment."
  }
}

run "prod_disables_the_scheduler" {
  command = plan

  variables {
    environment = "prod"
  }

  assert {
    condition     = length(aws_lambda_function.scheduler) == 0 && length(aws_iam_role.scheduler) == 0
    error_message = "prod's auto_shutdown is false, so no scheduler Lambda/role/log group is created."
  }

  assert {
    condition     = length(aws_cloudwatch_event_rule.start_instances) == 0 && length(aws_cloudwatch_event_rule.stop_instances) == 0
    error_message = "prod has no schedule_on/schedule_off, so no start/stop EventBridge rules are created."
  }
}

run "rejects_an_unrecognized_environment" {
  command = plan

  variables {
    environment = "qa"
  }

  expect_failures = [var.environment]
}

run "rejects_a_non_kms_key" {
  command = plan

  variables {
    kms_key_arn = "alias/aws/sns"
  }

  expect_failures = [var.kms_key_arn]
}

run "rejects_tags_without_environment" {
  command = plan

  variables {
    tags = { Tenant = "fnx" }
  }

  expect_failures = [var.tags]
}
