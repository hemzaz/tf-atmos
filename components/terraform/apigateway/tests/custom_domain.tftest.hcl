# Mock-provider tests for the built-in custom domain support (REST API):
# no AWS credentials, no network. Run from the component directory with
# `terraform init -backend=false && terraform test`.
#
# This is the path serverless-api/apigateway (stacks/catalog/templates/
# serverless-api.yaml) exercises: domain_name + certificate_arn + zone_id +
# base_path = "" directly on the apigateway component, the way
# cloudposse-terraform-components/aws-api-gateway-rest-api configures its
# custom domain, instead of a separate domain component.

mock_provider "aws" {}

variables {
  region   = "eu-west-2"
  api_name = "serverless-api"
  api_type = "REST"
  tags = {
    Environment = "test"
    Tenant      = "fnx"
    ManagedBy   = "Terraform"
  }
}

run "no_domain_resources_without_domain_name_and_certificate" {
  command = plan

  assert {
    condition     = length(aws_api_gateway_domain_name.rest_domain) == 0 && length(aws_api_gateway_base_path_mapping.rest_mapping) == 0 && length(aws_route53_record.api_domain) == 0
    error_message = "No custom-domain resources without both domain_name and certificate_arn."
  }

  assert {
    condition     = output.rest_api_domain_name == null && output.domain_name_route53_record == null
    error_message = "Domain outputs are null without a custom domain."
  }
}

run "domain_name_without_certificate_is_skipped" {
  command = plan

  variables {
    domain_name = "api.example.com"
  }

  assert {
    condition     = length(aws_api_gateway_domain_name.rest_domain) == 0
    error_message = "domain_name alone (no certificate_arn) must not create the custom domain (README: silently skipped)."
  }
}

run "root_base_path_mapping_at_tls_1_2_regional" {
  command = plan

  variables {
    domain_name     = "api.example.com"
    certificate_arn = "arn:aws:acm:eu-west-2:123456789012:certificate/11111111-1111-1111-1111-111111111111"
    base_path       = ""
    zone_id         = "Z1234567890EXAMPLE"
  }

  assert {
    condition     = aws_api_gateway_domain_name.rest_domain[0].domain_name == "api.example.com"
    error_message = "The custom domain name reaches the REST API's aws_api_gateway_domain_name."
  }

  assert {
    condition     = aws_api_gateway_domain_name.rest_domain[0].regional_certificate_arn == "arn:aws:acm:eu-west-2:123456789012:certificate/11111111-1111-1111-1111-111111111111"
    error_message = "certificate_arn reaches regional_certificate_arn."
  }

  assert {
    condition     = aws_api_gateway_domain_name.rest_domain[0].security_policy == "TLS_1_2"
    error_message = "The custom domain's security_policy is always TLS_1_2."
  }

  assert {
    condition     = contains(one(aws_api_gateway_domain_name.rest_domain[0].endpoint_configuration).types, "REGIONAL")
    error_message = "The custom domain's endpoint is REGIONAL, matching endpoint_type."
  }

  assert {
    condition     = aws_api_gateway_base_path_mapping.rest_mapping[0].base_path == ""
    error_message = "base_path = \"\" maps the stage at the domain root."
  }

  assert {
    condition     = aws_api_gateway_base_path_mapping.rest_mapping[0].stage_name == aws_api_gateway_stage.rest_stage[0].stage_name
    error_message = "The base path mapping targets the REST API's own stage."
  }
}

run "route53_alias_created_when_zone_id_is_set" {
  # apply, not plan: the alias target compares regional_domain_name, an
  # AWS-computed attribute that is unknown until the (mocked) domain name
  # resource is created.
  command = apply

  variables {
    domain_name     = "api.example.com"
    certificate_arn = "arn:aws:acm:eu-west-2:123456789012:certificate/11111111-1111-1111-1111-111111111111"
    base_path       = ""
    zone_id         = "Z1234567890EXAMPLE"
    # Unrelated to the domain/alias under test; off so the mock provider's
    # made-up log group ARN does not fail access_log_settings' own ARN check.
    enable_logging = false
  }

  assert {
    condition     = aws_route53_record.api_domain[0].zone_id == "Z1234567890EXAMPLE"
    error_message = "The alias record is created in the given zone_id."
  }

  assert {
    condition     = aws_route53_record.api_domain[0].name == "api.example.com"
    error_message = "The alias record's name is the custom domain_name."
  }

  assert {
    condition     = one(aws_route53_record.api_domain[0].alias).name == aws_api_gateway_domain_name.rest_domain[0].regional_domain_name
    error_message = "The alias targets the REST domain's own regional_domain_name."
  }
}

run "no_route53_record_without_zone_id" {
  command = plan

  variables {
    domain_name     = "api.example.com"
    certificate_arn = "arn:aws:acm:eu-west-2:123456789012:certificate/11111111-1111-1111-1111-111111111111"
    base_path       = ""
  }

  assert {
    condition     = length(aws_route53_record.api_domain) == 0 && output.domain_name_route53_record == null
    error_message = "zone_id must be non-null or the alias record is skipped too (README)."
  }

  assert {
    condition     = length(aws_api_gateway_domain_name.rest_domain) == 1
    error_message = "The custom domain itself does not need zone_id, only its alias record does."
  }
}

run "non_regional_endpoint_with_domain_fails_precondition" {
  # regional_certificate_arn (used unconditionally above) only works with a
  # REGIONAL endpoint; EDGE/PRIVATE would plan fine and fail at apply. The
  # precondition on aws_api_gateway_domain_name.rest_domain catches this at
  # plan time instead.
  command = plan

  variables {
    domain_name     = "api.example.com"
    certificate_arn = "arn:aws:acm:eu-west-2:123456789012:certificate/11111111-1111-1111-1111-111111111111"
    base_path       = ""
    endpoint_type   = ["EDGE"]
  }

  expect_failures = [aws_api_gateway_domain_name.rest_domain]
}
