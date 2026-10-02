# One CloudFront distribution per instance, named <Environment>-<name>, in
# front of an optional S3 bucket (through origin access control, OAC) and
# custom origins (ALB, API Gateway), with ordered cache behaviors and
# CloudFront Functions / Lambda@Edge associations. Modelled on
# cloudposse/terraform-aws-cloudfront-s3-cdn (the module behind Cloud Posse's
# aws-spa-s3-cloudfront component), whose input names this component reuses
# where they fit (custom_origins, ordered_cache, function_association,
# lambda_function_association).
# Deviations from upstream:
#   - The S3 origin is optional (origin_bucket_regional_domain_name null), so a
#     distribution can serve custom origins only; default_origin_id picks the
#     default behavior's origin ("" for the S3 origin, as upstream's
#     target_origin_id ""). Without an S3 origin there is no OAC.
#   - default_root_object defaults to index.html only when the default
#     behavior targets the S3 origin (upstream: always index.html).
#   - custom_origins and ordered_cache differences are listed beside those
#     variables in variables.tf. Origin groups (failover), s3_origins and
#     trusted signers / key groups are not modelled.
#   - The bucket is not created here and its policy is not written here
#     (upstream creates the bucket, or overrides an existing bucket's policy
#     with a statement for this one distribution's ARN).
#   - Trust boundary: account-scoped, deliberately. The origin s3 instance
#     sets allow_cloudfront_oac_read and the stack's kms sets
#     allow_cloudfront, which let ANY CloudFront distribution of this account
#     (aws:SourceAccount + AWS:SourceArn distribution/*) read the bucket and
#     decrypt with the key. Neither needs this distribution's ARN, so the
#     bucket and key deploy before the distribution and the first deploy
#     works in one pass. s3_origin_policy_json (this distribution only) is an
#     optional later tightening through the s3 source_policy_documents.
#   - OAC only, signing always with sigv4 (upstream defaults to an origin
#     access identity and makes the signing behavior an input).
#   - The default cache behavior uses cache, origin request and response
#     headers policies (managed names or IDs), never forwarded_values; the
#     defaults are the managed CachingOptimized and SecurityHeadersPolicy
#     (upstream defaults to forwarded_values and no response headers policy).
#   - minimum_protocol_version defaults to TLSv1.2_2021 and older policies are
#     rejected; ssl_support_method is always sni-only; http_version defaults to
#     http2and3 (upstream: http2); viewer_protocol_policy cannot be allow-all.
#   - Access logging is CloudFront standard logging v2 (CloudWatch Logs
#     delivery) to an existing bucket, off by default; upstream uses legacy
#     logging to a log bucket it creates.
#   - The SPA fallback (403/404 -> 200 /index.html) is a switch,
#     enable_spa_fallback, on top of upstream's custom_error_response.
#   - Names follow this repo (<Environment>-<name>), not the null-label id.

locals {
  enabled = var.enabled
  name    = "${var.tags["Environment"]}-${var.name}"

  s3_origin_enabled = var.origin_bucket_regional_domain_name != null
  origin_id         = "s3-${local.name}"

  # <bucket>.s3.<region>.amazonaws.com (validated), so the bucket's name and
  # ARN come from the one input the s3 component outputs.
  origin_bucket = local.s3_origin_enabled ? regex("^(.+)\\.s3\\.[a-z0-9-]+\\.amazonaws\\.com$", coalesce(var.origin_bucket_regional_domain_name, "-"))[0] : null

  # "" names the S3 origin (Cloud Posse's target_origin_id ""); anything else
  # is a custom origin's origin_id (both validated).
  default_origin_id   = var.default_origin_id == "" ? local.origin_id : var.default_origin_id
  default_root_object = var.default_root_object != null ? var.default_root_object : (var.default_origin_id == "" ? "index.html" : null)

  ordered_cache = [for c in var.ordered_cache : merge(c, {
    target_origin_id           = c.target_origin_id == "" ? local.origin_id : c.target_origin_id
    cache_policy_id            = lookup(local.managed_cache_policies, c.cache_policy_id, c.cache_policy_id)
    origin_request_policy_id   = c.origin_request_policy_id == null ? null : lookup(local.managed_origin_request_policies, c.origin_request_policy_id, c.origin_request_policy_id)
    response_headers_policy_id = c.response_headers_policy_id == "" ? null : lookup(local.managed_response_headers_policies, c.response_headers_policy_id, c.response_headers_policy_id)
  })]

  # Cloud Posse names of the AWS managed policies; any other value is a policy
  # ID (validated). IDs from the CloudFront Developer Guide ("Use managed ...
  # policies").
  managed_cache_policies = {
    CachingOptimized                          = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    CachingOptimizedForUncompressedObjects    = "b2884449-e4de-46a7-ac36-70bc7f1ddd6d"
    CachingDisabled                           = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    UseOriginCacheControlHeaders              = "83da9c7e-98b4-4e11-a168-04f0df8e2c65"
    UseOriginCacheControlHeaders-QueryStrings = "4cc15a8a-d715-48a4-82b8-cc0b614638fe"
  }
  managed_origin_request_policies = {
    AllViewer                             = "216adef6-5c7f-47e4-b989-5492eafa07d3"
    AllViewerAndCloudFrontHeaders-2022-06 = "33f36d7e-f396-46d9-90e0-52428a34d9dc"
    AllViewerExceptHostHeader             = "b689b0a8-53d0-40ab-baf2-68738e2966ac"
    CORS-CustomOrigin                     = "59781a5b-3903-41f3-afcb-af62929ccde1"
    CORS-S3Origin                         = "88a5eaf4-2fd4-4709-b370-b4c650ea3fcf"
    HostHeaderOnly                        = "bf0718e1-ba1e-49d1-88b1-f726733018ae"
    UserAgentRefererHeaders               = "acba4595-bd28-49b8-b9fe-13317c0390fa"
  }
  managed_response_headers_policies = {
    SecurityHeadersPolicy                         = "67f7725c-6f97-4210-82d7-5512b31e9d03"
    CORS-and-SecurityHeadersPolicy                = "e61eb60c-9c35-4d20-a928-2b84e02af89c"
    CORS-With-Preflight                           = "5cc3b908-e619-4b99-88e5-2cf7f45965bd"
    CORS-with-preflight-and-SecurityHeadersPolicy = "eaab4381-ed33-4a86-88ca-d9558dc6cd63"
    SimpleCORS                                    = "60669652-455b-4ae9-85a4-c4c02393f86c"
  }

  cache_policy_id            = lookup(local.managed_cache_policies, var.cache_policy_id, var.cache_policy_id)
  origin_request_policy_id   = var.origin_request_policy_id == null ? null : lookup(local.managed_origin_request_policies, var.origin_request_policy_id, var.origin_request_policy_id)
  response_headers_policy_id = var.response_headers_policy_id == null ? null : lookup(local.managed_response_headers_policies, var.response_headers_policy_id, var.response_headers_policy_id)

  # SPA routing: S3 answers 403 (no s3:ListBucket) or 404 for a client-side
  # route; serve the app shell with 200 instead. The fallback needs a root
  # object (validated); the empty string only keeps the template valid.
  spa_error_responses = [for code in [403, 404] : {
    error_code            = code
    response_code         = 200
    response_page_path    = "/${local.default_root_object != null ? local.default_root_object : ""}"
    error_caching_min_ttl = 0
  }]
  custom_error_responses = concat(var.custom_error_response, var.enable_spa_fallback ? local.spa_error_responses : [])

  # One A (and, with IPv6, AAAA) alias record per alias, Cloud Posse's
  # dns_alias_enabled into parent_zone_id.
  dns_records = local.enabled && var.dns_alias_enabled ? {
    for pair in setproduct(var.aliases, var.ipv6_enabled ? ["A", "AAAA"] : ["A"]) : "${pair[0]}/${pair[1]}" => {
      name = pair[0]
      type = pair[1]
    }
  } : {}
}

data "aws_partition" "current" {}

resource "aws_cloudfront_origin_access_control" "this" {
  count = local.enabled && local.s3_origin_enabled ? 1 : 0

  name                              = local.name
  description                       = "S3 origin ${local.origin_bucket} of ${local.name}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"

  lifecycle {
    precondition {
      condition     = length(local.name) <= 64
      error_message = "The distribution name (<Environment>-<name>, \"${local.name}\") must be 64 characters or fewer (the origin access control name limit)."
    }
  }
}

resource "aws_cloudfront_distribution" "this" {
  # checkov:skip=CKV_AWS_86:Access logging is an input (logging_enabled, standard logging v2), set per instance with a log bucket
  # checkov:skip=CKV_AWS_68:web_acl_id is an input; a CLOUDFRONT-scope waf instance is wired per instance
  # checkov:skip=CKV_AWS_310:Origin groups (failover) are not modelled; an instance has one origin per path
  # checkov:skip=CKV_AWS_374:Geo restriction is an input (geo_restriction_type), none by default as upstream
  # checkov:skip=CKV2_AWS_32:A response headers policy is attached (response_headers_policy_id, SecurityHeadersPolicy by default)
  # checkov:skip=CKV2_AWS_47:The WAF web ACL and its rules (Log4j included) come from the waf component through web_acl_id
  count = local.enabled ? 1 : 0

  enabled             = var.distribution_enabled
  comment             = coalesce(var.comment, local.name)
  aliases             = var.aliases
  default_root_object = local.default_root_object
  http_version        = var.http_version
  is_ipv6_enabled     = var.ipv6_enabled
  price_class         = var.price_class
  web_acl_id          = var.web_acl_id
  wait_for_deployment = var.wait_for_deployment

  dynamic "origin" {
    for_each = local.s3_origin_enabled ? [local.origin_id] : []
    content {
      origin_id                = origin.value
      domain_name              = var.origin_bucket_regional_domain_name
      origin_path              = var.origin_path
      origin_access_control_id = aws_cloudfront_origin_access_control.this[0].id
    }
  }

  dynamic "origin" {
    for_each = var.custom_origins
    content {
      origin_id   = origin.value.origin_id
      domain_name = origin.value.domain_name
      origin_path = origin.value.origin_path

      # Header values are often a shared secret (the ALB origin-verify
      # header): keep them out of plan output. This hides the whole origin
      # set in plan diffs; the values are still in state.
      dynamic "custom_header" {
        for_each = origin.value.custom_headers
        content {
          name  = custom_header.value.name
          value = sensitive(custom_header.value.value)
        }
      }

      custom_origin_config {
        http_port                = origin.value.custom_origin_config.http_port
        https_port               = origin.value.custom_origin_config.https_port
        origin_protocol_policy   = origin.value.custom_origin_config.origin_protocol_policy
        origin_ssl_protocols     = origin.value.custom_origin_config.origin_ssl_protocols
        origin_keepalive_timeout = origin.value.custom_origin_config.origin_keepalive_timeout
        origin_read_timeout      = origin.value.custom_origin_config.origin_read_timeout
      }

      dynamic "origin_shield" {
        for_each = try(origin.value.origin_shield.enabled, false) ? [origin.value.origin_shield] : []
        content {
          enabled              = origin_shield.value.enabled
          origin_shield_region = origin_shield.value.region
        }
      }
    }
  }

  default_cache_behavior {
    target_origin_id           = local.default_origin_id
    viewer_protocol_policy     = var.viewer_protocol_policy
    allowed_methods            = var.allowed_methods
    cached_methods             = var.cached_methods
    compress                   = var.compress
    cache_policy_id            = local.cache_policy_id
    origin_request_policy_id   = local.origin_request_policy_id
    response_headers_policy_id = local.response_headers_policy_id

    dynamic "function_association" {
      for_each = var.function_association
      content {
        event_type   = function_association.value.event_type
        function_arn = function_association.value.function_arn
      }
    }

    dynamic "lambda_function_association" {
      for_each = var.lambda_function_association
      content {
        event_type   = lambda_function_association.value.event_type
        lambda_arn   = lambda_function_association.value.lambda_arn
        include_body = lambda_function_association.value.include_body
      }
    }
  }

  # List order is precedence (first match wins), as upstream.
  dynamic "ordered_cache_behavior" {
    for_each = local.ordered_cache
    content {
      path_pattern               = ordered_cache_behavior.value.path_pattern
      target_origin_id           = ordered_cache_behavior.value.target_origin_id
      viewer_protocol_policy     = ordered_cache_behavior.value.viewer_protocol_policy
      allowed_methods            = ordered_cache_behavior.value.allowed_methods
      cached_methods             = ordered_cache_behavior.value.cached_methods
      compress                   = ordered_cache_behavior.value.compress
      cache_policy_id            = ordered_cache_behavior.value.cache_policy_id
      origin_request_policy_id   = ordered_cache_behavior.value.origin_request_policy_id
      response_headers_policy_id = ordered_cache_behavior.value.response_headers_policy_id

      dynamic "function_association" {
        for_each = ordered_cache_behavior.value.function_association
        content {
          event_type   = function_association.value.event_type
          function_arn = function_association.value.function_arn
        }
      }

      dynamic "lambda_function_association" {
        for_each = ordered_cache_behavior.value.lambda_function_association
        content {
          event_type   = lambda_function_association.value.event_type
          lambda_arn   = lambda_function_association.value.lambda_arn
          include_body = lambda_function_association.value.include_body
        }
      }
    }
  }

  dynamic "custom_error_response" {
    for_each = local.custom_error_responses
    content {
      error_code            = custom_error_response.value.error_code
      response_code         = custom_error_response.value.response_code
      response_page_path    = custom_error_response.value.response_page_path
      error_caching_min_ttl = custom_error_response.value.error_caching_min_ttl
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = var.geo_restriction_type
      locations        = var.geo_restriction_locations
    }
  }

  # With aliases, the ACM certificate (us-east-1, validated) over SNI only;
  # without, the *.cloudfront.net certificate, whose minimum protocol AWS fixes.
  viewer_certificate {
    acm_certificate_arn            = var.acm_certificate_arn
    cloudfront_default_certificate = var.acm_certificate_arn == null
    ssl_support_method             = var.acm_certificate_arn == null ? null : "sni-only"
    minimum_protocol_version       = var.acm_certificate_arn == null ? "TLSv1" : var.minimum_protocol_version
  }

  tags = { Name = local.name }
}

# The statement the origin bucket's policy needs (Cloud Posse's
# s3_origin_access_control policy document): this distribution only, through
# its OAC, may read objects. Optional: the s3 allow_cloudfront_oac_read
# statement already covers every distribution of the account; this tightens
# it through the s3 component's source_policy_documents.
locals {
  s3_origin_policy_json = local.enabled && local.s3_origin_enabled ? jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "CloudFrontOACRead${replace(local.name, "/[^A-Za-z0-9]/", "")}"
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "arn:${data.aws_partition.current.partition}:s3:::${local.origin_bucket}/*"
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = aws_cloudfront_distribution.this[0].arn
        }
      }
    }]
  }) : null
}

# Standard logging v2: CloudWatch Logs delivery of ACCESS_LOGS to an S3
# bucket. CloudFront delivery sources exist only in us-east-1, whatever the
# stack's region (provider 6.x per-resource region).
resource "aws_cloudwatch_log_delivery_source" "this" {
  count = local.enabled && var.logging_enabled ? 1 : 0

  region       = "us-east-1"
  name         = "${local.name}-cloudfront"
  log_type     = "ACCESS_LOGS"
  resource_arn = aws_cloudfront_distribution.this[0].arn
  lifecycle {
    precondition {
      condition     = can(regex("^[\\w-]{1,60}$", "${local.name}-cloudfront-s3"))
      error_message = "The logging v2 delivery names (\"${local.name}-cloudfront\", \"${local.name}-cloudfront-s3\") must be 1-60 characters of letters, digits, underscore or hyphen: shorten name or Environment."
    }
  }
}

resource "aws_cloudwatch_log_delivery_destination" "this" {
  count = local.enabled && var.logging_enabled ? 1 : 0

  region        = "us-east-1"
  name          = "${local.name}-cloudfront-s3"
  output_format = var.log_output_format

  delivery_destination_configuration {
    destination_resource_arn = var.access_log_bucket_arn
  }
  lifecycle {
    precondition {
      condition     = can(regex("^[\\w-]{1,60}$", "${local.name}-cloudfront-s3"))
      error_message = "The logging v2 delivery names (\"${local.name}-cloudfront\", \"${local.name}-cloudfront-s3\") must be 1-60 characters of letters, digits, underscore or hyphen: shorten name or Environment."
    }
  }
}

resource "aws_cloudwatch_log_delivery" "this" {
  count = local.enabled && var.logging_enabled ? 1 : 0

  region                   = "us-east-1"
  delivery_source_name     = aws_cloudwatch_log_delivery_source.this[0].name
  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.this[0].arn

  s3_delivery_configuration = [{
    suffix_path                 = var.log_prefix
    enable_hive_compatible_path = false
  }]
}

resource "aws_route53_record" "alias" {
  for_each = local.dns_records

  zone_id = var.parent_zone_id
  name    = each.value.name
  type    = each.value.type

  alias {
    name                   = aws_cloudfront_distribution.this[0].domain_name
    zone_id                = aws_cloudfront_distribution.this[0].hosted_zone_id
    evaluate_target_health = false
  }
}
