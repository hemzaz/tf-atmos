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
