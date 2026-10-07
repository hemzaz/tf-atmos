# Mock-provider tests for the multi-region failover record (B1 DR) and the
# MOCK liveness method its health check probes: no AWS credentials, no
# network. Run from the component directory with
# `terraform init -backend=false && terraform test`.

mock_provider "aws" {}

variables {
  region          = "us-east-2"
  api_name        = "prod-main-api"
  api_type        = "REST"
  stage_name      = "v1"
  domain_name     = "api.example.com"
  certificate_arn = "arn:aws:acm:us-east-2:123456789012:certificate/11111111-1111-1111-1111-111111111111"
  zone_id         = "Z1234567890EXAMPLE"
  api_methods = [{
    resource_path = "/"
    http_method   = "GET"
    authorization = "NONE"
  }]
  api_integrations = [{
    resource_path           = "/"
    http_method             = "GET"
    integration_http_method = "GET"
    type                    = "MOCK"
  }]
  tags = {
    Environment = "ue2"
    Tenant      = "fnx"
    ManagedBy   = "Terraform"
  }
}

run "mock_liveness_answers_200" {
  command = plan

  assert {
    condition     = aws_api_gateway_integration.integration["GET /"].request_templates["application/json"] == jsonencode({ statusCode = 200 })
    error_message = "A MOCK without request_templates must get one selecting statusCode 200."
  }

  assert {
    condition     = aws_api_gateway_method_response.mock["GET /"].status_code == "200" && aws_api_gateway_integration_response.mock["GET /"].status_code == "200"
    error_message = "A MOCK needs a 200 method response and integration response, or API Gateway answers 500."
  }
}

run "simple_record_without_failover" {
  command = plan

  assert {
    condition     = length(aws_route53_health_check.api) == 0 && aws_route53_record.api_domain[0].set_identifier == null && length(aws_route53_record.api_domain[0].failover_routing_policy) == 0
    error_message = "Without route53_failover_type the record stays simple, with no health check."
  }
}

run "secondary_record_with_its_own_health_check" {
  command = plan

  variables {
    route53_failover_type  = "SECONDARY"
    route53_set_identifier = "ue2"
  }

  assert {
    condition = (
      aws_route53_record.api_domain[0].set_identifier == "ue2"
      && aws_route53_record.api_domain[0].failover_routing_policy[0].type == "SECONDARY"
      && aws_route53_record.api_domain[0].name == "api.example.com"
    )
    error_message = "The record must be the SECONDARY half of the failover pair, under its own set_identifier."
  }

  assert {
    condition = (
      aws_route53_health_check.api[0].type == "HTTPS"
      && aws_route53_health_check.api[0].port == 443
      && aws_route53_health_check.api[0].resource_path == "/v1/"
    )
    error_message = "The health check must probe this region's stage root over HTTPS."
  }
}

run "health_check_alarm_in_us_east_1_notifies_the_topic" {
  command = plan

  variables {
    route53_failover_type      = "SECONDARY"
    route53_set_identifier     = "ue2"
    health_check_alarm_actions = ["arn:aws:sns:us-east-1:123456789012:ue1-main-alarms"]
  }

  assert {
    condition = (
      length(aws_cloudwatch_metric_alarm.health_check) == 1
      && aws_cloudwatch_metric_alarm.health_check[0].region == "us-east-1"
      && aws_cloudwatch_metric_alarm.health_check[0].namespace == "AWS/Route53"
      && aws_cloudwatch_metric_alarm.health_check[0].metric_name == "HealthCheckStatus"
      && aws_cloudwatch_metric_alarm.health_check[0].comparison_operator == "LessThanThreshold"
      && aws_cloudwatch_metric_alarm.health_check[0].threshold == 1
    )
    error_message = "A failover health check needs an alarm on its HealthCheckStatus."
  }

  assert {
    condition = (
      aws_cloudwatch_metric_alarm.health_check[0].alarm_actions == toset(["arn:aws:sns:us-east-1:123456789012:ue1-main-alarms"])
      && aws_cloudwatch_metric_alarm.health_check[0].ok_actions == toset(["arn:aws:sns:us-east-1:123456789012:ue1-main-alarms"])
    )
    error_message = "The alarm must notify health_check_alarm_actions on failure and on recovery."
  }
}

run "no_health_check_alarm_without_failover" {
  command = plan

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.health_check) == 0
    error_message = "No health check, no alarm."
  }
}

run "health_check_alarm_topic_outside_us_east_1_is_rejected" {
  command = plan

  variables {
    route53_failover_type      = "SECONDARY"
    route53_set_identifier     = "ue2"
    health_check_alarm_actions = ["arn:aws:sns:us-east-2:123456789012:ue2-main-alarms"]
  }

  expect_failures = [var.health_check_alarm_actions]
}

run "geo_blocking_pins_the_us_checker_regions" {
  command = plan

  variables {
    route53_failover_type  = "PRIMARY"
    route53_set_identifier = "ue1"
    enable_waf             = true
    allowed_countries      = ["US", "CA"]
  }

  assert {
    condition     = aws_route53_health_check.api[0].regions == toset(["us-east-1", "us-west-1", "us-west-2"])
    error_message = "With a WAF geo rule the health check must call only from US checker regions."
  }
}

run "geo_blocking_without_us_is_rejected" {
  command = plan

  variables {
    route53_failover_type  = "PRIMARY"
    route53_set_identifier = "ue1"
    allowed_countries      = ["DE"]
  }

  expect_failures = [var.route53_failover_type]
}

run "liveness_method_needing_an_api_key_is_rejected" {
  command = plan

  variables {
    route53_failover_type  = "PRIMARY"
    route53_set_identifier = "ue1"
    api_methods = [{
      resource_path    = "/"
      http_method      = "GET"
      authorization    = "NONE"
      api_key_required = true
    }]
  }

  expect_failures = [var.route53_failover_type]
}

run "failover_without_a_root_method_is_rejected" {
  command = plan

  variables {
    route53_failover_type  = "PRIMARY"
    route53_set_identifier = "ue1"
    api_resources          = [{ path_part = "health" }]
    api_methods = [{
      resource_path = "/health"
      http_method   = "GET"
    }]
    api_integrations = [{
      resource_path           = "/health"
      http_method             = "GET"
      integration_http_method = "GET"
      type                    = "MOCK"
    }]
  }

  expect_failures = [var.route53_failover_type]
}

run "failover_without_a_set_identifier_is_rejected" {
  command = plan

  variables {
    route53_failover_type = "PRIMARY"
  }

  expect_failures = [var.route53_failover_type]
}

run "failover_without_a_zone_is_rejected" {
  command = plan

  variables {
    route53_failover_type  = "PRIMARY"
    route53_set_identifier = "ue1"
    zone_id                = null
  }

  expect_failures = [var.route53_failover_type]
}

run "unknown_failover_type_is_rejected" {
  command = plan

  variables {
    route53_failover_type  = "WEIGHTED"
    route53_set_identifier = "ue1"
  }

  expect_failures = [var.route53_failover_type]
}
