# Mock-provider tests: no AWS credentials, no network. Run from the component
# directory with `terraform init -backend=false && terraform test`.

# override_during = plan: mocked computed values (ARNs, IDs) are known at plan,
# so plan-only runs can assert on the policy JSON and the alias records.
mock_provider "aws" {
  override_during = plan

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_resource "aws_cloudfront_distribution" {
    defaults = {
      id             = "E2EXAMPLE12345"
      arn            = "arn:aws:cloudfront::123456789012:distribution/E2EXAMPLE12345"
      domain_name    = "d111111abcdef8.cloudfront.net"
      hosted_zone_id = "Z2FDTNDATAQYW2"
    }
  }

  mock_resource "aws_cloudfront_origin_access_control" {
    defaults = {
      id = "E1OACEXAMPLE"
    }
  }

  mock_resource "aws_cloudwatch_log_delivery_destination" {
    defaults = {
      arn = "arn:aws:logs:us-east-1:123456789012:delivery-destination:test-site-cloudfront-s3"
    }
  }
}

variables {
  region = "us-east-1"
  name   = "site"
  tags = {
    Environment = "test"
    Tenant      = "fnx"
    ManagedBy   = "Terraform"
  }
  origin_bucket_regional_domain_name = "test-site-123456789012.s3.us-east-1.amazonaws.com"
}

run "s3_origin_with_oac" {
  command = plan

  assert {
    condition = (
      aws_cloudfront_origin_access_control.this[0].name == "test-site"
      && aws_cloudfront_origin_access_control.this[0].origin_access_control_origin_type == "s3"
      && aws_cloudfront_origin_access_control.this[0].signing_behavior == "always"
      && aws_cloudfront_origin_access_control.this[0].signing_protocol == "sigv4"
    )
    error_message = "The OAC is <Environment>-<name>, for S3, always signing with sigv4."
  }

  assert {
    condition = (
      length(aws_cloudfront_distribution.this[0].origin) == 1
      && one(aws_cloudfront_distribution.this[0].origin).domain_name == "test-site-123456789012.s3.us-east-1.amazonaws.com"
      && one(aws_cloudfront_distribution.this[0].origin).origin_id == "s3-test-site"
      && one(aws_cloudfront_distribution.this[0].origin).origin_access_control_id == "E1OACEXAMPLE"
      && aws_cloudfront_distribution.this[0].default_cache_behavior[0].target_origin_id == "s3-test-site"
    )
    error_message = "One S3 origin, reached through the OAC, is the default behavior's target."
  }

  assert {
    condition = (
      aws_cloudfront_distribution.this[0].default_cache_behavior[0].viewer_protocol_policy == "redirect-to-https"
      && aws_cloudfront_distribution.this[0].default_cache_behavior[0].cache_policy_id == "658327ea-f89d-4fab-a63d-7e88639e58f6"
      && aws_cloudfront_distribution.this[0].default_cache_behavior[0].response_headers_policy_id == "67f7725c-6f97-4210-82d7-5512b31e9d03"
      && aws_cloudfront_distribution.this[0].default_cache_behavior[0].origin_request_policy_id == null
      && aws_cloudfront_distribution.this[0].default_cache_behavior[0].compress
    )
    error_message = "Defaults: redirect-to-https, managed CachingOptimized and SecurityHeadersPolicy, no origin request policy, compression."
  }

  assert {
    condition = (
      aws_cloudfront_distribution.this[0].http_version == "http2and3"
      && aws_cloudfront_distribution.this[0].is_ipv6_enabled
      && aws_cloudfront_distribution.this[0].price_class == "PriceClass_100"
      && aws_cloudfront_distribution.this[0].default_root_object == "index.html"
      && aws_cloudfront_distribution.this[0].comment == "test-site"
      && aws_cloudfront_distribution.this[0].web_acl_id == null
      && aws_cloudfront_distribution.this[0].restrictions[0].geo_restriction[0].restriction_type == "none"
      && length(aws_cloudfront_distribution.this[0].custom_error_response) == 0
    )
    error_message = "Defaults: http2and3, IPv6, PriceClass_100, index.html, no WAF, no geo restriction, no error responses."
  }

  assert {
    condition = (
      aws_cloudfront_distribution.this[0].viewer_certificate[0].cloudfront_default_certificate
      && aws_cloudfront_distribution.this[0].viewer_certificate[0].acm_certificate_arn == null
      && length(aws_route53_record.alias) == 0
      && length(aws_cloudwatch_log_delivery.this) == 0
    )
    error_message = "Without a certificate the default certificate is used, and there are no DNS records or log delivery."
  }

  assert {
    condition = (
      output.distribution_id == "E2EXAMPLE12345"
      && output.distribution_arn == "arn:aws:cloudfront::123456789012:distribution/E2EXAMPLE12345"
      && output.distribution_domain_name == "d111111abcdef8.cloudfront.net"
      && output.distribution_hosted_zone_id == "Z2FDTNDATAQYW2"
      && output.origin_access_control_id == "E1OACEXAMPLE"
    )
    error_message = "The distribution and OAC outputs are set."
  }
}

run "s3_origin_policy_json" {
  command = plan

  assert {
    condition = (
      length(jsondecode(output.s3_origin_policy_json).Statement) == 1
      && jsondecode(output.s3_origin_policy_json).Statement[0].Sid == "CloudFrontOACReadtestsite"
      && jsondecode(output.s3_origin_policy_json).Statement[0].Effect == "Allow"
      && jsondecode(output.s3_origin_policy_json).Statement[0].Principal.Service == "cloudfront.amazonaws.com"
      && jsondecode(output.s3_origin_policy_json).Statement[0].Action == "s3:GetObject"
      && jsondecode(output.s3_origin_policy_json).Statement[0].Resource == "arn:aws:s3:::test-site-123456789012/*"
    )
    error_message = "The policy lets the CloudFront service read the origin bucket's objects only, with a Sid unique per distribution."
  }

  assert {
    condition     = jsondecode(output.s3_origin_policy_json).Statement[0].Condition.StringEquals["AWS:SourceArn"] == "arn:aws:cloudfront::123456789012:distribution/E2EXAMPLE12345"
    error_message = "The policy is limited to this distribution (AWS:SourceArn)."
  }
}

run "dotted_bucket_name" {
  command = plan

  variables {
    origin_bucket_regional_domain_name = "assets.example.com.s3.us-east-2.amazonaws.com"
  }

  assert {
    condition     = jsondecode(output.s3_origin_policy_json).Statement[0].Resource == "arn:aws:s3:::assets.example.com/*"
    error_message = "A bucket name with dots is derived whole from the regional domain name."
  }
}

run "aliases_certificate_and_dns_records" {
  command = plan

  variables {
    aliases                  = ["www.example.com", "example.com"]
    acm_certificate_arn      = "arn:aws:acm:us-east-1:123456789012:certificate/11111111-2222-3333-4444-555555555555"
    minimum_protocol_version = "TLSv1.2_2025"
    dns_alias_enabled        = true
    parent_zone_id           = "Z0123456789ABCDEFGHIJ"
  }

  assert {
    condition = (
      toset(aws_cloudfront_distribution.this[0].aliases) == toset(["www.example.com", "example.com"])
      && aws_cloudfront_distribution.this[0].viewer_certificate[0].acm_certificate_arn == var.acm_certificate_arn
      && aws_cloudfront_distribution.this[0].viewer_certificate[0].cloudfront_default_certificate == false
      && aws_cloudfront_distribution.this[0].viewer_certificate[0].ssl_support_method == "sni-only"
      && aws_cloudfront_distribution.this[0].viewer_certificate[0].minimum_protocol_version == "TLSv1.2_2025"
    )
    error_message = "Aliases are served with the ACM certificate over SNI at the chosen TLS policy."
  }

  assert {
    condition = (
      length(aws_route53_record.alias) == 4
      && aws_route53_record.alias["www.example.com/A"].zone_id == "Z0123456789ABCDEFGHIJ"
      && aws_route53_record.alias["www.example.com/AAAA"].type == "AAAA"
      && aws_route53_record.alias["example.com/A"].name == "example.com"
      && one(aws_route53_record.alias["example.com/AAAA"].alias).name == "d111111abcdef8.cloudfront.net"
      && one(aws_route53_record.alias["example.com/AAAA"].alias).zone_id == "Z2FDTNDATAQYW2"
      && one(aws_route53_record.alias["example.com/AAAA"].alias).evaluate_target_health == false
    )
    error_message = "Each alias gets an A and an AAAA alias record to the distribution in parent_zone_id."
  }
}

run "dns_records_without_ipv6" {
  command = plan

  variables {
    aliases             = ["www.example.com"]
    acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/11111111-2222-3333-4444-555555555555"
    dns_alias_enabled   = true
    parent_zone_id      = "Z0123456789ABCDEFGHIJ"
    ipv6_enabled        = false
  }

  assert {
    condition = (
      keys(aws_route53_record.alias) == ["www.example.com/A"]
      && aws_cloudfront_distribution.this[0].viewer_certificate[0].minimum_protocol_version == "TLSv1.2_2021"
    )
    error_message = "Without IPv6 only A records are created; the TLS policy defaults to TLSv1.2_2021."
  }
}

run "spa_fallback" {
  command = plan

  variables {
    enable_spa_fallback = true
    custom_error_response = [{
      error_code            = 500
      response_code         = 500
      response_page_path    = "/500.html"
      error_caching_min_ttl = 10
    }]
  }

  assert {
    condition = (
      length(aws_cloudfront_distribution.this[0].custom_error_response) == 3
      && length([for r in aws_cloudfront_distribution.this[0].custom_error_response : r if contains([403, 404], r.error_code) && r.response_code == 200 && r.response_page_path == "/index.html" && r.error_caching_min_ttl == 0]) == 2
      && length([for r in aws_cloudfront_distribution.this[0].custom_error_response : r if r.error_code == 500 && r.response_page_path == "/500.html"]) == 1
    )
    error_message = "The SPA fallback answers 403 and 404 with 200 /index.html, next to the custom error responses."
  }
}

run "managed_policy_names_ids_waf_geo_logging" {
  command = plan

  variables {
    cache_policy_id            = "CachingDisabled"
    origin_request_policy_id   = "CORS-S3Origin"
    response_headers_policy_id = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    web_acl_id                 = "arn:aws:wafv2:us-east-1:123456789012:global/webacl/test-cdn/a1b2c3d4-5678-90ab-cdef-111111111111"
    geo_restriction_type       = "whitelist"
    geo_restriction_locations  = ["US", "DE"]
    logging_enabled            = true
    access_log_bucket_arn      = "arn:aws:s3:::test-cdn-logs"
    log_prefix                 = "cloudfront/site"
    region                     = "us-east-2"
  }

  assert {
    condition = (
      aws_cloudfront_distribution.this[0].default_cache_behavior[0].cache_policy_id == "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
      && aws_cloudfront_distribution.this[0].default_cache_behavior[0].origin_request_policy_id == "88a5eaf4-2fd4-4709-b370-b4c650ea3fcf"
      && aws_cloudfront_distribution.this[0].default_cache_behavior[0].response_headers_policy_id == "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    )
    error_message = "Managed policy names resolve to their IDs; a policy ID passes through."
  }

  assert {
    condition = (
      aws_cloudfront_distribution.this[0].web_acl_id == var.web_acl_id
      && aws_cloudfront_distribution.this[0].restrictions[0].geo_restriction[0].restriction_type == "whitelist"
      && toset(aws_cloudfront_distribution.this[0].restrictions[0].geo_restriction[0].locations) == toset(["US", "DE"])
    )
    error_message = "The WAF web ACL and the geo restriction are applied."
  }

  assert {
    condition = (
      aws_cloudwatch_log_delivery_source.this[0].log_type == "ACCESS_LOGS"
      && aws_cloudwatch_log_delivery_source.this[0].region == "us-east-1"
      && aws_cloudwatch_log_delivery_source.this[0].resource_arn == "arn:aws:cloudfront::123456789012:distribution/E2EXAMPLE12345"
      && aws_cloudwatch_log_delivery_destination.this[0].region == "us-east-1"
      && aws_cloudwatch_log_delivery_destination.this[0].output_format == "json"
      && one(aws_cloudwatch_log_delivery_destination.this[0].delivery_destination_configuration).destination_resource_arn == "arn:aws:s3:::test-cdn-logs"
      && aws_cloudwatch_log_delivery.this[0].delivery_destination_arn == "arn:aws:logs:us-east-1:123456789012:delivery-destination:test-site-cloudfront-s3"
      && aws_cloudwatch_log_delivery.this[0].s3_delivery_configuration[0].suffix_path == "cloudfront/site"
    )
    error_message = "Logging v2 delivers ACCESS_LOGS from us-east-1 (whatever the stack region) to the log bucket."
  }
}

run "disabled_creates_nothing" {
  command = plan

  variables {
    enabled = false
  }

  assert {
    condition = (
      length(aws_cloudfront_distribution.this) == 0 && length(aws_cloudfront_origin_access_control.this) == 0
      && output.distribution_arn == null && output.s3_origin_policy_json == null
    )
    error_message = "enabled = false creates no resources."
  }
}

# Negative validations.

run "rejects_certificate_outside_us_east_1" {
  command = plan

  variables {
    acm_certificate_arn = "arn:aws:acm:us-east-2:123456789012:certificate/11111111-2222-3333-4444-555555555555"
  }

  expect_failures = [var.acm_certificate_arn]
}

run "rejects_aliases_without_certificate" {
  command = plan

  variables {
    aliases = ["www.example.com"]
  }

  expect_failures = [var.aliases]
}

run "rejects_regional_web_acl" {
  command = plan

  variables {
    web_acl_id = "arn:aws:wafv2:us-east-1:123456789012:regional/webacl/test-api/a1b2c3d4-5678-90ab-cdef-111111111111"
  }

  expect_failures = [var.web_acl_id]
}

run "rejects_unknown_price_class" {
  command = plan

  variables {
    price_class = "PriceClass_300"
  }

  expect_failures = [var.price_class]
}

run "rejects_old_tls_policy" {
  command = plan

  variables {
    minimum_protocol_version = "TLSv1.1_2016"
  }

  expect_failures = [var.minimum_protocol_version]
}

run "rejects_bucket_name_for_origin" {
  command = plan

  variables {
    origin_bucket_regional_domain_name = "test-site-123456789012"
  }

  expect_failures = [var.origin_bucket_regional_domain_name]
}

run "rejects_unknown_managed_policy_name" {
  command = plan

  variables {
    cache_policy_id = "Managed-CachingOptimized"
  }

  expect_failures = [var.cache_policy_id]
}

run "rejects_spa_fallback_with_404_response" {
  command = plan

  variables {
    enable_spa_fallback   = true
    custom_error_response = [{ error_code = 404, response_code = 404, response_page_path = "/404.html" }]
  }

  expect_failures = [var.enable_spa_fallback]
}

run "rejects_dns_alias_without_zone" {
  command = plan

  variables {
    aliases             = ["www.example.com"]
    acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/11111111-2222-3333-4444-555555555555"
    dns_alias_enabled   = true
  }

  expect_failures = [var.parent_zone_id]
}

run "rejects_logging_without_bucket" {
  command = plan

  variables {
    logging_enabled = true
  }

  expect_failures = [var.access_log_bucket_arn]
}

run "rejects_geo_type_without_locations" {
  command = plan

  variables {
    geo_restriction_type = "blacklist"
  }

  expect_failures = [var.geo_restriction_locations]
}

run "rejects_allow_all_viewer_protocol" {
  command = plan

  variables {
    viewer_protocol_policy = "allow-all"
  }

  expect_failures = [var.viewer_protocol_policy]
}

run "rejects_period_in_name" {
  command = plan

  variables {
    name = "www.site"
  }

  expect_failures = [var.name]
}

run "rejects_log_delivery_names_over_60_characters" {
  command = plan

  variables {
    tags = {
      Environment = "a-long-environment-name"
    }
    name                  = "a-thirty-character-site-name12"
    logging_enabled       = true
    access_log_bucket_arn = "arn:aws:s3:::test-cdn-logs"
  }

  expect_failures = [aws_cloudwatch_log_delivery_source.this, aws_cloudwatch_log_delivery_destination.this]
}

run "rejects_log_prefix_with_leading_slash" {
  command = plan

  variables {
    log_prefix = "/cloudfront"
  }

  expect_failures = [var.log_prefix]
}
