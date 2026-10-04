# Mock-provider tests for custom origins, ordered cache behaviors and edge
# function associations. No AWS credentials, no network. Run from the
# component directory with `terraform init -backend=false && terraform test`.

mock_provider "aws" {
  override_during = plan

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_data "aws_ssm_parameter" {
    defaults = {
      value = "Origin-Verify-0123456789abcdef"
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
}

variables {
  region = "us-east-1"
  name   = "site"
  tags = {
    Environment = "test"
  }
  origin_bucket_regional_domain_name = "test-site-123456789012.s3.us-east-1.amazonaws.com"
}

run "alb_only_distribution" {
  command = plan

  variables {
    origin_bucket_regional_domain_name = null
    custom_origins = [{
      domain_name    = "origin.app.example.com"
      origin_id      = "alb"
      custom_headers = [{ name = "X-Origin-Verify", value = "s3cr3t-shared-value" }]
    }]
    default_origin_id        = "alb"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cache_policy_id          = "CachingDisabled"
    origin_request_policy_id = "AllViewerExceptHostHeader"
  }

  assert {
    condition = (
      length(aws_cloudfront_origin_access_control.this) == 0
      && length(aws_cloudfront_distribution.this[0].origin) == 1
      && output.origin_access_control_id == null
      && output.s3_origin_policy_json == null
    )
    error_message = "Without an S3 origin there is no OAC, no S3 origin and no bucket policy."
  }

  assert {
    condition = (
      one(aws_cloudfront_distribution.this[0].origin).origin_id == "alb"
      && one(aws_cloudfront_distribution.this[0].origin).domain_name == "origin.app.example.com"
      && one(aws_cloudfront_distribution.this[0].origin).origin_access_control_id == null
      && one(one(aws_cloudfront_distribution.this[0].origin).custom_origin_config).origin_protocol_policy == "https-only"
      && toset(one(one(aws_cloudfront_distribution.this[0].origin).custom_origin_config).origin_ssl_protocols) == toset(["TLSv1.2"])
      && one(one(aws_cloudfront_distribution.this[0].origin).custom_origin_config).https_port == 443
      && one(one(aws_cloudfront_distribution.this[0].origin).custom_origin_config).http_port == 80
      && one(one(aws_cloudfront_distribution.this[0].origin).custom_origin_config).origin_read_timeout == 30
      && one(one(aws_cloudfront_distribution.this[0].origin).custom_origin_config).origin_keepalive_timeout == 5
      && length(one(aws_cloudfront_distribution.this[0].origin).origin_shield) == 0
    )
    error_message = "The ALB origin defaults to https-only, TLSv1.2, ports 80/443, read 30 s, keepalive 5 s, no origin shield."
  }

  assert {
    condition = (
      one(one(aws_cloudfront_distribution.this[0].origin).custom_header).name == "X-Origin-Verify"
      && nonsensitive(one(one(aws_cloudfront_distribution.this[0].origin).custom_header).value) == "s3cr3t-shared-value"
    )
    error_message = "The origin-verify header is sent to the ALB."
  }

  assert {
    condition = (
      aws_cloudfront_distribution.this[0].default_cache_behavior[0].target_origin_id == "alb"
      && aws_cloudfront_distribution.this[0].default_cache_behavior[0].cache_policy_id == "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
      && aws_cloudfront_distribution.this[0].default_cache_behavior[0].origin_request_policy_id == "b689b0a8-53d0-40ab-baf2-68738e2966ac"
      && length(aws_cloudfront_distribution.this[0].default_cache_behavior[0].allowed_methods) == 7
      && aws_cloudfront_distribution.this[0].default_root_object == null
      && length(aws_cloudfront_distribution.this[0].ordered_cache_behavior) == 0
    )
    error_message = "The default behavior targets the ALB with the chosen policies, and no root object is set for a custom default origin."
  }
}

run "custom_header_value_read_from_ssm" {
  command = plan

  variables {
    origin_bucket_regional_domain_name = null
    custom_origins = [{
      domain_name    = "origin.app.example.com"
      origin_id      = "alb"
      custom_headers = [{ name = "X-Origin-Verify", value_ssm_parameter_name = "/webapp/origin-verify" }]
    }]
    default_origin_id = "alb"
  }

  assert {
    condition = (
      length(data.aws_ssm_parameter.custom_header) == 1
      && data.aws_ssm_parameter.custom_header["/webapp/origin-verify"].name == "/webapp/origin-verify"
      && one(one(aws_cloudfront_distribution.this[0].origin).custom_header).name == "X-Origin-Verify"
      && nonsensitive(one(one(aws_cloudfront_distribution.this[0].origin).custom_header).value) == "Origin-Verify-0123456789abcdef"
    )
    error_message = "A value_ssm_parameter_name header sends the SSM parameter's value."
  }
}

run "literal_custom_header_reads_no_parameter" {
  command = plan

  variables {
    origin_bucket_regional_domain_name = null
    custom_origins = [{
      domain_name    = "origin.app.example.com"
      origin_id      = "alb"
      custom_headers = [{ name = "X-Origin-Verify", value = "s3cr3t-shared-value" }]
    }]
    default_origin_id = "alb"
  }

  assert {
    condition     = length(data.aws_ssm_parameter.custom_header) == 0
    error_message = "A literal header value reads no SSM parameter."
  }
}

run "rejects_custom_header_with_value_and_parameter" {
  command = plan

  variables {
    custom_origins = [{
      domain_name    = "origin.app.example.com"
      origin_id      = "alb"
      custom_headers = [{ name = "X-Origin-Verify", value = "s3cr3t-shared-value", value_ssm_parameter_name = "/webapp/origin-verify" }]
    }]
  }

  expect_failures = [var.custom_origins]
}

run "rejects_custom_header_without_a_value" {
  command = plan

  variables {
    custom_origins = [{
      domain_name    = "origin.app.example.com"
      origin_id      = "alb"
      custom_headers = [{ name = "X-Origin-Verify" }]
    }]
  }

  expect_failures = [var.custom_origins]
}

run "s3_and_api_origins_with_ordered_behaviors" {
  command = plan

  variables {
    custom_origins = [{
      domain_name = "abc123defg.execute-api.us-east-1.amazonaws.com"
      origin_id   = "api"
      origin_path = "/prod"
    }]
    ordered_cache = [
      {
        path_pattern               = "/api/*"
        target_origin_id           = "api"
        allowed_methods            = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
        cache_policy_id            = "CachingDisabled"
        origin_request_policy_id   = "AllViewerExceptHostHeader"
        response_headers_policy_id = ""
        viewer_protocol_policy     = "https-only"
      },
      {
        path_pattern = "/static/*"
      },
    ]
  }

  assert {
    condition = (
      length(aws_cloudfront_distribution.this[0].origin) == 2
      && one([for o in aws_cloudfront_distribution.this[0].origin : o.origin_path if o.origin_id == "api"]) == "/prod"
      && one([for o in aws_cloudfront_distribution.this[0].origin : o.origin_access_control_id if o.origin_id == "s3-test-site"]) == "E1OACEXAMPLE"
      && aws_cloudfront_distribution.this[0].default_cache_behavior[0].target_origin_id == "s3-test-site"
      && aws_cloudfront_distribution.this[0].default_root_object == "index.html"
    )
    error_message = "The S3 origin (default target, index.html) and the API origin are both defined."
  }

  assert {
    condition = (
      length(aws_cloudfront_distribution.this[0].ordered_cache_behavior) == 2
      && aws_cloudfront_distribution.this[0].ordered_cache_behavior[0].path_pattern == "/api/*"
      && aws_cloudfront_distribution.this[0].ordered_cache_behavior[0].target_origin_id == "api"
      && aws_cloudfront_distribution.this[0].ordered_cache_behavior[0].viewer_protocol_policy == "https-only"
      && length(aws_cloudfront_distribution.this[0].ordered_cache_behavior[0].allowed_methods) == 7
      && aws_cloudfront_distribution.this[0].ordered_cache_behavior[0].cache_policy_id == "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
      && aws_cloudfront_distribution.this[0].ordered_cache_behavior[0].origin_request_policy_id == "b689b0a8-53d0-40ab-baf2-68738e2966ac"
      && aws_cloudfront_distribution.this[0].ordered_cache_behavior[0].response_headers_policy_id == null
    )
    error_message = "The /api/* behavior comes first, targets the API with the mapped policies and no response headers policy."
  }

  assert {
    condition = (
      aws_cloudfront_distribution.this[0].ordered_cache_behavior[1].path_pattern == "/static/*"
      && aws_cloudfront_distribution.this[0].ordered_cache_behavior[1].target_origin_id == "s3-test-site"
      && aws_cloudfront_distribution.this[0].ordered_cache_behavior[1].viewer_protocol_policy == "redirect-to-https"
      && toset(aws_cloudfront_distribution.this[0].ordered_cache_behavior[1].allowed_methods) == toset(["GET", "HEAD", "OPTIONS"])
      && toset(aws_cloudfront_distribution.this[0].ordered_cache_behavior[1].cached_methods) == toset(["GET", "HEAD"])
      && aws_cloudfront_distribution.this[0].ordered_cache_behavior[1].compress
      && aws_cloudfront_distribution.this[0].ordered_cache_behavior[1].cache_policy_id == "658327ea-f89d-4fab-a63d-7e88639e58f6"
      && aws_cloudfront_distribution.this[0].ordered_cache_behavior[1].origin_request_policy_id == null
      && aws_cloudfront_distribution.this[0].ordered_cache_behavior[1].response_headers_policy_id == "67f7725c-6f97-4210-82d7-5512b31e9d03"
    )
    error_message = "A behavior with target \"\" targets the S3 origin with the default behavior's defaults."
  }
}

run "function_and_lambda_associations" {
  command = plan

  variables {
    function_association = [{
      event_type   = "viewer-request"
      function_arn = "arn:aws:cloudfront::123456789012:function/test-rewrite"
    }]
    lambda_function_association = [{
      event_type   = "origin-request"
      lambda_arn   = "arn:aws:lambda:us-east-1:123456789012:function:test-auth:3"
      include_body = true
    }]
    ordered_cache = [{
      path_pattern = "/app/*"
      function_association = [
        { event_type = "viewer-request", function_arn = "arn:aws:cloudfront::123456789012:function/test-rewrite" },
        { event_type = "viewer-response", function_arn = "arn:aws:cloudfront::123456789012:function/test-headers" },
      ]
      lambda_function_association = [{
        event_type = "origin-response"
        lambda_arn = "arn:aws:lambda:us-east-1:123456789012:function:test-cache:12"
      }]
    }]
  }

  assert {
    condition = (
      length(aws_cloudfront_distribution.this[0].default_cache_behavior[0].function_association) == 1
      && one(aws_cloudfront_distribution.this[0].default_cache_behavior[0].function_association).event_type == "viewer-request"
      && one(aws_cloudfront_distribution.this[0].default_cache_behavior[0].function_association).function_arn == "arn:aws:cloudfront::123456789012:function/test-rewrite"
      && one(aws_cloudfront_distribution.this[0].default_cache_behavior[0].lambda_function_association).event_type == "origin-request"
      && one(aws_cloudfront_distribution.this[0].default_cache_behavior[0].lambda_function_association).lambda_arn == "arn:aws:lambda:us-east-1:123456789012:function:test-auth:3"
      && one(aws_cloudfront_distribution.this[0].default_cache_behavior[0].lambda_function_association).include_body
    )
    error_message = "The default behavior carries its CloudFront Function and Lambda@Edge associations."
  }

  assert {
    condition = (
      length(aws_cloudfront_distribution.this[0].ordered_cache_behavior[0].function_association) == 2
      && toset([for f in aws_cloudfront_distribution.this[0].ordered_cache_behavior[0].function_association : f.event_type]) == toset(["viewer-request", "viewer-response"])
      && one(aws_cloudfront_distribution.this[0].ordered_cache_behavior[0].lambda_function_association).event_type == "origin-response"
      && one(aws_cloudfront_distribution.this[0].ordered_cache_behavior[0].lambda_function_association).include_body == false
    )
    error_message = "An ordered behavior carries two CloudFront Functions (one per viewer event) and a Lambda@Edge function."
  }
}

run "origin_tuning_and_shield" {
  command = plan

  variables {
    custom_origins = [{
      domain_name = "legacy.example.com"
      origin_id   = "legacy"
      custom_origin_config = {
        http_port                = 8080
        origin_protocol_policy   = "match-viewer"
        origin_read_timeout      = 60
        origin_keepalive_timeout = 10
      }
      origin_shield = { enabled = true, region = "us-east-2" }
    }]
  }

  assert {
    condition = (
      one([for o in aws_cloudfront_distribution.this[0].origin : one(o.custom_origin_config).http_port if o.origin_id == "legacy"]) == 8080
      && one([for o in aws_cloudfront_distribution.this[0].origin : one(o.custom_origin_config).https_port if o.origin_id == "legacy"]) == 443
      && one([for o in aws_cloudfront_distribution.this[0].origin : one(o.custom_origin_config).origin_protocol_policy if o.origin_id == "legacy"]) == "match-viewer"
      && one([for o in aws_cloudfront_distribution.this[0].origin : one(o.custom_origin_config).origin_read_timeout if o.origin_id == "legacy"]) == 60
      && one([for o in aws_cloudfront_distribution.this[0].origin : one(o.custom_origin_config).origin_keepalive_timeout if o.origin_id == "legacy"]) == 10
      && one([for o in aws_cloudfront_distribution.this[0].origin : one(o.origin_shield).origin_shield_region if o.origin_id == "legacy"]) == "us-east-2"
      && one([for o in aws_cloudfront_distribution.this[0].origin : one(o.origin_shield).enabled if o.origin_id == "legacy"])
    )
    error_message = "Ports, protocol policy, timeouts and origin shield are passed through; unset fields keep their defaults."
  }
}

run "spa_fallback_on_custom_default_origin" {
  command = plan

  variables {
    origin_bucket_regional_domain_name = null
    custom_origins                     = [{ domain_name = "site.example.com", origin_id = "web" }]
    default_origin_id                  = "web"
    default_root_object                = "app.html"
    enable_spa_fallback                = true
  }

  assert {
    condition = (
      aws_cloudfront_distribution.this[0].default_root_object == "app.html"
      && length([for r in aws_cloudfront_distribution.this[0].custom_error_response : r if r.response_page_path == "/app.html"]) == 2
    )
    error_message = "An explicit default_root_object is used on a custom default origin, and by the SPA fallback."
  }
}

# Negative validations.

run "rejects_no_origin" {
  command = plan

  variables {
    origin_bucket_regional_domain_name = null
  }

  expect_failures = [var.default_origin_id]
}

run "rejects_unknown_default_origin" {
  command = plan

  variables {
    custom_origins    = [{ domain_name = "origin.app.example.com", origin_id = "alb" }]
    default_origin_id = "api"
  }

  expect_failures = [var.default_origin_id]
}

run "rejects_duplicate_origin_ids" {
  command = plan

  variables {
    custom_origins = [
      { domain_name = "a.example.com", origin_id = "app" },
      { domain_name = "b.example.com", origin_id = "app" },
    ]
  }

  expect_failures = [var.custom_origins]
}

run "rejects_origin_id_of_the_s3_origin" {
  command = plan

  variables {
    custom_origins = [{ domain_name = "a.example.com", origin_id = "s3-test-site" }]
  }

  expect_failures = [var.custom_origins]
}

run "rejects_domain_name_with_scheme" {
  command = plan

  variables {
    custom_origins = [{ domain_name = "https://a.example.com", origin_id = "app" }]
  }

  expect_failures = [var.custom_origins]
}

run "rejects_unknown_origin_protocol_policy" {
  command = plan

  variables {
    custom_origins = [{ domain_name = "a.example.com", origin_id = "app", custom_origin_config = { origin_protocol_policy = "https" } }]
  }

  expect_failures = [var.custom_origins]
}

run "rejects_sslv3" {
  command = plan

  variables {
    custom_origins = [{ domain_name = "a.example.com", origin_id = "app", custom_origin_config = { origin_ssl_protocols = ["SSLv3", "TLSv1.2"] } }]
  }

  expect_failures = [var.custom_origins]
}

run "rejects_read_timeout_over_180" {
  command = plan

  variables {
    custom_origins = [{ domain_name = "a.example.com", origin_id = "app", custom_origin_config = { origin_read_timeout = 181 } }]
  }

  expect_failures = [var.custom_origins]
}

run "rejects_keepalive_timeout_zero" {
  command = plan

  variables {
    custom_origins = [{ domain_name = "a.example.com", origin_id = "app", custom_origin_config = { origin_keepalive_timeout = 0 } }]
  }

  expect_failures = [var.custom_origins]
}

run "rejects_reserved_port" {
  command = plan

  variables {
    custom_origins = [{ domain_name = "a.example.com", origin_id = "app", custom_origin_config = { https_port = 444 } }]
  }

  expect_failures = [var.custom_origins]
}

run "rejects_origin_shield_without_region" {
  command = plan

  variables {
    custom_origins = [{ domain_name = "a.example.com", origin_id = "app", origin_shield = { enabled = true } }]
  }

  expect_failures = [var.custom_origins]
}

run "rejects_duplicate_custom_header_names" {
  command = plan

  variables {
    custom_origins = [{
      domain_name    = "a.example.com"
      origin_id      = "app"
      custom_headers = [{ name = "X-Origin-Verify", value = "a" }, { name = "x-origin-verify", value = "b" }]
    }]
  }

  expect_failures = [var.custom_origins]
}

run "rejects_unknown_ordered_target" {
  command = plan

  variables {
    ordered_cache = [{ path_pattern = "/api/*", target_origin_id = "api" }]
  }

  expect_failures = [var.ordered_cache]
}

run "rejects_ordered_s3_target_without_s3_origin" {
  command = plan

  variables {
    origin_bucket_regional_domain_name = null
    custom_origins                     = [{ domain_name = "origin.app.example.com", origin_id = "alb" }]
    default_origin_id                  = "alb"
    ordered_cache                      = [{ path_pattern = "/static/*" }]
  }

  expect_failures = [var.ordered_cache]
}

run "rejects_duplicate_path_patterns" {
  command = plan

  variables {
    ordered_cache = [{ path_pattern = "/static/*" }, { path_pattern = "/static/*", compress = false }]
  }

  expect_failures = [var.ordered_cache]
}

run "rejects_ordered_allow_all" {
  command = plan

  variables {
    ordered_cache = [{ path_pattern = "/static/*", viewer_protocol_policy = "allow-all" }]
  }

  expect_failures = [var.ordered_cache]
}

run "rejects_ordered_unknown_cache_policy" {
  command = plan

  variables {
    ordered_cache = [{ path_pattern = "/static/*", cache_policy_id = "Managed-CachingDisabled" }]
  }

  expect_failures = [var.ordered_cache]
}

run "rejects_lambda_outside_us_east_1" {
  command = plan

  variables {
    lambda_function_association = [{ event_type = "origin-request", lambda_arn = "arn:aws:lambda:eu-west-1:123456789012:function:test-auth:3" }]
  }

  expect_failures = [var.lambda_function_association]
}

run "rejects_lambda_latest" {
  command = plan

  variables {
    lambda_function_association = [{ event_type = "origin-request", lambda_arn = "arn:aws:lambda:us-east-1:123456789012:function:test-auth:$LATEST" }]
  }

  expect_failures = [var.lambda_function_association]
}

run "rejects_unqualified_lambda_in_ordered_behavior" {
  command = plan

  variables {
    ordered_cache = [{
      path_pattern                = "/app/*"
      lambda_function_association = [{ event_type = "origin-request", lambda_arn = "arn:aws:lambda:us-east-1:123456789012:function:test-auth" }]
    }]
  }

  expect_failures = [var.ordered_cache]
}

run "rejects_include_body_on_response_event" {
  command = plan

  variables {
    lambda_function_association = [{ event_type = "origin-response", include_body = true, lambda_arn = "arn:aws:lambda:us-east-1:123456789012:function:test-auth:3" }]
  }

  expect_failures = [var.lambda_function_association]
}

run "rejects_two_functions_for_one_event" {
  command = plan

  variables {
    function_association = [
      { event_type = "viewer-request", function_arn = "arn:aws:cloudfront::123456789012:function/a" },
      { event_type = "viewer-request", function_arn = "arn:aws:cloudfront::123456789012:function/b" },
    ]
  }

  expect_failures = [var.function_association]
}

run "rejects_function_on_origin_event" {
  command = plan

  variables {
    function_association = [{ event_type = "origin-request", function_arn = "arn:aws:cloudfront::123456789012:function/a" }]
  }

  expect_failures = [var.function_association]
}

run "rejects_three_functions_in_ordered_behavior" {
  command = plan

  variables {
    ordered_cache = [{
      path_pattern = "/app/*"
      function_association = [
        { event_type = "viewer-request", function_arn = "arn:aws:cloudfront::123456789012:function/a" },
        { event_type = "viewer-response", function_arn = "arn:aws:cloudfront::123456789012:function/b" },
        { event_type = "viewer-request", function_arn = "arn:aws:cloudfront::123456789012:function/c" },
      ]
    }]
  }

  expect_failures = [var.ordered_cache]
}

run "rejects_function_and_lambda_on_one_viewer_event" {
  command = plan

  variables {
    function_association        = [{ event_type = "viewer-request", function_arn = "arn:aws:cloudfront::123456789012:function/a" }]
    lambda_function_association = [{ event_type = "viewer-request", lambda_arn = "arn:aws:lambda:us-east-1:123456789012:function:test-auth:3" }]
  }

  expect_failures = [var.lambda_function_association]
}

run "rejects_function_viewer_request_with_lambda_viewer_response" {
  command = plan

  variables {
    function_association        = [{ event_type = "viewer-request", function_arn = "arn:aws:cloudfront::123456789012:function/a" }]
    lambda_function_association = [{ event_type = "viewer-response", lambda_arn = "arn:aws:lambda:us-east-1:123456789012:function:test-auth:3" }]
  }

  expect_failures = [var.lambda_function_association]
}

run "rejects_function_viewer_response_with_lambda_viewer_request_in_ordered_behavior" {
  command = plan

  variables {
    ordered_cache = [{
      path_pattern                = "/app/*"
      function_association        = [{ event_type = "viewer-response", function_arn = "arn:aws:cloudfront::123456789012:function/a" }]
      lambda_function_association = [{ event_type = "viewer-request", lambda_arn = "arn:aws:lambda:us-east-1:123456789012:function:test-auth:3" }]
    }]
  }

  expect_failures = [var.ordered_cache]
}

run "rejects_denied_custom_header_name" {
  command = plan

  variables {
    custom_origins = [{ domain_name = "a.example.com", origin_id = "app", custom_headers = [{ name = "Host", value = "a" }] }]
  }

  expect_failures = [var.custom_origins]
}

run "rejects_x_amz_custom_header" {
  command = plan

  variables {
    custom_origins = [{ domain_name = "a.example.com", origin_id = "app", custom_headers = [{ name = "X-Amz-Secret", value = "a" }] }]
  }

  expect_failures = [var.custom_origins]
}

run "rejects_cached_methods_outside_allowed_methods" {
  command = plan

  variables {
    allowed_methods = ["GET", "HEAD"]
    cached_methods  = ["GET", "HEAD", "OPTIONS"]
  }

  expect_failures = [var.cached_methods]
}

run "rejects_ordered_cached_methods_outside_allowed_methods" {
  command = plan

  variables {
    ordered_cache = [{ path_pattern = "/static/*", allowed_methods = ["GET", "HEAD"], cached_methods = ["GET", "HEAD", "OPTIONS"] }]
  }

  expect_failures = [var.ordered_cache]
}

run "rejects_spa_fallback_on_custom_default_without_root_object" {
  command = plan

  variables {
    origin_bucket_regional_domain_name = null
    custom_origins                     = [{ domain_name = "site.example.com", origin_id = "web" }]
    default_origin_id                  = "web"
    enable_spa_fallback                = true
  }

  expect_failures = [var.enable_spa_fallback]
}
