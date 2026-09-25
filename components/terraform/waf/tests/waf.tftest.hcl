# Mock-provider tests: no AWS credentials, no network. Run from the component
# directory with `terraform init -backend=false && terraform test`.

mock_provider "aws" {}

variables {
  region = "eu-west-2"
  name   = "webapp-waf"
  scope  = "REGIONAL"
  tags = {
    Environment = "test"
    Tenant      = "fnx"
    ManagedBy   = "Terraform"
  }
}

run "cloudfront_scope_is_rejected_outside_us_east_1" {
  command = plan

  variables {
    region = "eu-west-2"
    scope  = "CLOUDFRONT"
  }

  expect_failures = [var.scope]
}

run "cloudfront_scope_is_accepted_in_us_east_1" {
  command = plan

  variables {
    region = "us-east-1"
    scope  = "CLOUDFRONT"
  }

  assert {
    condition     = aws_wafv2_web_acl.this[0].scope == "CLOUDFRONT"
    error_message = "A CLOUDFRONT-scope ACL in us-east-1 is accepted."
  }

  assert {
    condition     = length(aws_wafv2_web_acl_association.this) == 0
    error_message = "No association resource is created for CLOUDFRONT."
  }
}

run "association_arns_are_rejected_for_cloudfront_scope" {
  command = plan

  variables {
    region                    = "us-east-1"
    scope                     = "CLOUDFRONT"
    association_resource_arns = ["arn:aws:cloudfront::123456789012:distribution/EDFDVBD6EXAMPLE"]
  }

  expect_failures = [var.association_resource_arns]
}

run "a_null_association_arn_is_rejected_with_a_clear_message" {
  command = plan

  # Regression for a null entry reaching this variable -- e.g. from an
  # upstream apigateway rest_api_stage_arn output that is null when
  # api_type = "HTTP". Without the validation this would instead fail deep
  # inside aws_wafv2_web_acl_association's for_each (toset() of a list
  # containing null) with an opaque core error.
  variables {
    scope = "REGIONAL"
    association_resource_arns = [
      "arn:aws:elasticloadbalancing:eu-west-2:123456789012:loadbalancer/app/test-webapp-alb/abc123",
      null,
    ]
  }

  expect_failures = [var.association_resource_arns]
}

run "regional_scope_associates_every_arn" {
  command = plan

  variables {
    scope = "REGIONAL"
    association_resource_arns = [
      "arn:aws:elasticloadbalancing:eu-west-2:123456789012:loadbalancer/app/test-webapp-alb/abc123",
    ]
  }

  assert {
    condition     = length(aws_wafv2_web_acl_association.this) == 1
    error_message = "REGIONAL scope creates one association per resource_arn."
  }

  assert {
    condition     = one(values(aws_wafv2_web_acl_association.this)).resource_arn == "arn:aws:elasticloadbalancing:eu-west-2:123456789012:loadbalancer/app/test-webapp-alb/abc123"
    error_message = "The association targets the given resource ARN."
  }
}

run "log_group_name_always_starts_with_aws_waf_logs" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_group.this[0].name == "aws-waf-logs-test-webapp-waf"
    error_message = "WAFv2 requires the log group name to start with aws-waf-logs- (and aws-waf-logs-<Environment>-<name> is this component's convention)."
  }

  assert {
    condition     = startswith(aws_cloudwatch_log_group.this[0].name, "aws-waf-logs-")
    error_message = "The log group name starts with aws-waf-logs- regardless of the name given."
  }
}

run "logging_can_be_disabled" {
  command = plan

  variables {
    enable_logging = false
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.this) == 0 && length(aws_wafv2_web_acl_logging_configuration.this) == 0
    error_message = "No log group or logging configuration is created when enable_logging is false."
  }
}

run "log_resource_policy_can_be_skipped_to_stay_under_the_quota" {
  command = plan

  variables {
    manage_log_resource_policy = false
  }

  assert {
    condition     = length(aws_cloudwatch_log_resource_policy.waf_logging) == 0
    error_message = "No CloudWatch Logs resource policy is created when manage_log_resource_policy is false, so this instance falls back to the implicit AWSWAF-LOGS policy instead of consuming another quota slot."
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.this) == 1 && length(aws_wafv2_web_acl_logging_configuration.this) == 1
    error_message = "The log group and logging configuration are still created; only the explicit resource policy is skipped."
  }
}

run "rule_priorities_must_be_unique_across_all_rule_lists" {
  command = plan

  variables {
    managed_rule_group_statement_rules = [
      { name = "AWSManagedRulesCommonRuleSet", priority = 10 },
    ]
    rate_based_statement_rules = [
      { name = "RateLimit", priority = 10, limit = 2000 },
    ]
  }

  expect_failures = [var.byte_match_statement_rules]
}

run "unique_priorities_across_rule_lists_are_accepted" {
  command = plan

  variables {
    managed_rule_group_statement_rules = [
      { name = "AWSManagedRulesCommonRuleSet", priority = 10 },
    ]
    rate_based_statement_rules = [
      { name = "RateLimit", priority = 1, limit = 2000 },
    ]
    byte_match_statement_rules = [
      {
        name                  = "BlockBadUserAgents"
        priority              = 5
        search_string         = "curl/"
        positional_constraint = "STARTS_WITH"
        header_name           = "user-agent"
      },
    ]
  }

  assert {
    condition     = length(aws_wafv2_web_acl.this[0].rule) == 3
    error_message = "All three rule types are rendered onto the web ACL."
  }
}
