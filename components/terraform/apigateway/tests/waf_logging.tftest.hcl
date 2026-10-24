# Mock-provider tests for the inline web ACL's logging (enable_waf): no AWS
# credentials, no network. Run from the component directory with
# `terraform init -backend=false && terraform test`.

mock_provider "aws" {
  mock_resource "aws_wafv2_web_acl" {
    override_during = plan
    defaults = {
      arn = "arn:aws:wafv2:us-east-1:123456789012:regional/webacl/test-api-waf/mock"
    }
  }
  mock_resource "aws_cloudwatch_log_group" {
    override_during = plan
    defaults = {
      arn = "arn:aws:logs:us-east-1:123456789012:log-group:aws-waf-logs-test-api"
    }
  }
}

variables {
  region             = "us-east-1"
  api_name           = "api"
  api_type           = "REST"
  create_dashboard   = false
  enable_waf         = true
  log_retention_days = 90
  kms_key_id         = "arn:aws:kms:us-east-1:123456789012:key/mrk-mock"
  tags = {
    Environment = "test"
    Tenant      = "fnx"
    ManagedBy   = "Terraform"
  }

  api_methods      = [{ resource_path = "/", http_method = "GET", authorization = "NONE" }]
  api_integrations = [{ resource_path = "/", http_method = "GET", integration_http_method = "GET", type = "MOCK" }]
}

run "waf_logs_to_an_encrypted_aws_waf_logs_group" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_group.waf[0].name == "aws-waf-logs-test-api"
    error_message = "WAFv2 only logs to a log group named aws-waf-logs-*."
  }

  assert {
    condition     = aws_cloudwatch_log_group.waf[0].kms_key_id == var.kms_key_id && aws_cloudwatch_log_group.waf[0].retention_in_days == 90
    error_message = "The WAF log group takes kms_key_id and log_retention_days, as api_logs does."
  }

  assert {
    condition = (
      aws_wafv2_web_acl_logging_configuration.api_waf[0].resource_arn == aws_wafv2_web_acl.api_waf[0].arn
      && contains(aws_wafv2_web_acl_logging_configuration.api_waf[0].log_destination_configs, aws_cloudwatch_log_group.waf[0].arn)
      && length(aws_wafv2_web_acl_logging_configuration.api_waf[0].log_destination_configs) == 1
    )
    error_message = "The logging configuration ties the API's web ACL to its log group."
  }

  assert {
    condition = toset([
      for f in aws_wafv2_web_acl_logging_configuration.api_waf[0].redacted_fields : f.single_header[0].name
    ]) == toset(["authorization", "cookie"])
    error_message = "Authorization and Cookie are redacted from the WAF logs."
  }
}

run "waf_logging_can_be_turned_off" {
  command = plan

  variables {
    waf_logging_enabled = false
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.waf) == 0 && length(aws_wafv2_web_acl_logging_configuration.api_waf) == 0
    error_message = "waf_logging_enabled = false creates no WAF log group or logging configuration."
  }
}

run "no_waf_no_waf_logs" {
  command = plan

  variables {
    enable_waf = false
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.waf) == 0 && length(aws_wafv2_web_acl_logging_configuration.api_waf) == 0
    error_message = "Without enable_waf there is nothing to log."
  }
}
