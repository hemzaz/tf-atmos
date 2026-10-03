# Mock-provider tests for VPC origins (custom_origins[].vpc_origin). No AWS
# credentials, no network. Run from the component directory with
# `terraform init -backend=false && terraform test`.

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

  mock_resource "aws_cloudfront_vpc_origin" {
    defaults = {
      id  = "vo_EXAMPLE1234567890"
      arn = "arn:aws:cloudfront::123456789012:vpcorigin/vo_EXAMPLE1234567890"
    }
  }
}

variables {
  region = "us-east-1"
  name   = "webapp-cdn"
  tags = {
    Environment = "test"
  }
  origin_bucket_regional_domain_name = null
  default_origin_id                  = "alb"
}

run "internal_alb_vpc_origin" {
  command = plan

  variables {
    custom_origins = [{
      domain_name    = "origin.app.example.com"
      origin_id      = "alb"
      custom_headers = [{ name = "X-App-Edge", value = "cloudfront" }]
      vpc_origin = {
        arn                 = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/test-webapp-alb/0123456789abcdef"
        origin_read_timeout = 60
      }
    }]
  }

  assert {
    condition = (
      length(aws_cloudfront_vpc_origin.this) == 1
      && one(aws_cloudfront_vpc_origin.this["alb"].vpc_origin_endpoint_config).name == "test-webapp-cdn-alb-c6437398"
      && one(aws_cloudfront_vpc_origin.this["alb"].vpc_origin_endpoint_config).arn == "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/test-webapp-alb/0123456789abcdef"
      && one(aws_cloudfront_vpc_origin.this["alb"].vpc_origin_endpoint_config).origin_protocol_policy == "https-only"
      && one(aws_cloudfront_vpc_origin.this["alb"].vpc_origin_endpoint_config).https_port == 443
      && one(aws_cloudfront_vpc_origin.this["alb"].vpc_origin_endpoint_config).http_port == 80
      && toset(one(one(aws_cloudfront_vpc_origin.this["alb"].vpc_origin_endpoint_config).origin_ssl_protocols).items) == toset(["TLSv1.2"])
      && one(one(aws_cloudfront_vpc_origin.this["alb"].vpc_origin_endpoint_config).origin_ssl_protocols).quantity == 1
    )
    error_message = "One VPC origin, <Environment>-<name>-<origin_id>-<config hash>, for the ALB: https-only, TLSv1.2, ports 80/443 by default."
  }

  # The replacement trigger carries the whole endpoint config. c6437398 is the
  # first 8 hex digits of sha1 over the sorted-key, compact JSON of that
  # config (arn, http_port 80, https_port 443, https-only, [TLSv1.2]),
  # computed outside Terraform.
  assert {
    condition = (
      terraform_data.vpc_origin["alb"].input.name == "test-webapp-cdn-alb-c6437398"
      && terraform_data.vpc_origin["alb"].input.arn == "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/test-webapp-alb/0123456789abcdef"
      && terraform_data.vpc_origin["alb"].input.https_port == 443
      && terraform_data.vpc_origin["alb"].input.http_port == 80
      && terraform_data.vpc_origin["alb"].input.origin_protocol_policy == "https-only"
      && tolist(terraform_data.vpc_origin["alb"].input.origin_ssl_protocols) == tolist(["TLSv1.2"])
    )
    error_message = "terraform_data.vpc_origin's input is the VPC origin's endpoint config, name included."
  }

  assert {
    condition = (
      one(aws_cloudfront_distribution.this[0].origin).domain_name == "origin.app.example.com"
      && length(one(aws_cloudfront_distribution.this[0].origin).custom_origin_config) == 0
      && one(one(aws_cloudfront_distribution.this[0].origin).vpc_origin_config).vpc_origin_id == "vo_EXAMPLE1234567890"
      && one(one(aws_cloudfront_distribution.this[0].origin).vpc_origin_config).origin_read_timeout == 60
      && one(one(aws_cloudfront_distribution.this[0].origin).vpc_origin_config).origin_keepalive_timeout == 5
      && output.vpc_origin_ids == { alb = "vo_EXAMPLE1234567890" }
    )
    error_message = "The origin uses vpc_origin_config (the VPC origin's id and the timeouts), no custom_origin_config, and keeps its domain name."
  }

  assert {
    condition = (
      one(one(aws_cloudfront_distribution.this[0].origin).custom_header).name == "X-App-Edge"
      && nonsensitive(one(one(aws_cloudfront_distribution.this[0].origin).custom_header).value) == "cloudfront"
    )
    error_message = "A VPC origin still takes custom headers."
  }
}

# A config change (here https_port) changes the terraform_data input and the
# name, so the VPC origin is replaced (replace_triggered_by) under a name that
# does not collide with the one it replaces (create_before_destroy). Mock
# providers cannot show replacement or its ordering (create, repoint the
# distribution, delete): this proves the trigger's input changes, not the
# apply sequence.
run "config_change_changes_trigger_and_name" {
  command = plan

  variables {
    custom_origins = [{
      domain_name = "origin.app.example.com"
      origin_id   = "alb"
      vpc_origin = {
        arn        = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/test-webapp-alb/0123456789abcdef"
        https_port = 8443
      }
    }]
  }

  assert {
    condition = (
      terraform_data.vpc_origin["alb"].input.https_port == 8443
      && terraform_data.vpc_origin["alb"].input.name == "test-webapp-cdn-alb-35075613"
      && terraform_data.vpc_origin["alb"].input.name != "test-webapp-cdn-alb-c6437398"
      && one(aws_cloudfront_vpc_origin.this["alb"].vpc_origin_endpoint_config).name == "test-webapp-cdn-alb-35075613"
      && one(aws_cloudfront_vpc_origin.this["alb"].vpc_origin_endpoint_config).https_port == 8443
    )
    error_message = "Changing https_port changes the replacement trigger's input and the VPC origin's name (new hash)."
  }
}

run "nlb_and_ec2_vpc_origins_beside_a_public_origin" {
  command = plan

  variables {
    custom_origins = [
      {
        domain_name = "origin.app.example.com"
        origin_id   = "alb"
        vpc_origin = {
          arn                    = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/net/test-nlb/0123456789abcdef"
          origin_protocol_policy = "http-only"
          http_port              = 8080
        }
      },
      {
        domain_name = "ip-10-10-1-10.ec2.internal"
        origin_id   = "box"
        vpc_origin  = { arn = "arn:aws:ec2:us-east-1:123456789012:instance/i-0123456789abcdef0" }
      },
      { domain_name = "api.example.com", origin_id = "api" },
    ]
  }

  assert {
    condition = (
      toset(keys(aws_cloudfront_vpc_origin.this)) == toset(["alb", "box"])
      && one(aws_cloudfront_vpc_origin.this["alb"].vpc_origin_endpoint_config).origin_protocol_policy == "http-only"
      && one(aws_cloudfront_vpc_origin.this["alb"].vpc_origin_endpoint_config).http_port == 8080
      && one(aws_cloudfront_vpc_origin.this["box"].vpc_origin_endpoint_config).arn == "arn:aws:ec2:us-east-1:123456789012:instance/i-0123456789abcdef0"
    )
    error_message = "NLB and EC2 instance ARNs make VPC origins, with their transport passed through."
  }

  assert {
    condition = (
      one([for o in aws_cloudfront_distribution.this[0].origin : length(o.vpc_origin_config) if o.origin_id == "api"]) == 0
      && one([for o in aws_cloudfront_distribution.this[0].origin : one(o.custom_origin_config).origin_protocol_policy if o.origin_id == "api"]) == "https-only"
      && one([for o in aws_cloudfront_distribution.this[0].origin : length(o.custom_origin_config) if o.origin_id == "box"]) == 0
    )
    error_message = "A public origin without custom_origin_config keeps the custom_origin_config defaults and no VPC origin."
  }
}

run "viewer_lambda_allowed_on_vpc_origin" {
  command = plan

  variables {
    custom_origins = [{
      domain_name = "origin.app.example.com"
      origin_id   = "alb"
      vpc_origin  = { arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/test-webapp-alb/0123456789abcdef" }
    }]
    lambda_function_association = [{ event_type = "viewer-request", lambda_arn = "arn:aws:lambda:us-east-1:123456789012:function:auth:3" }]
  }

  assert {
    condition     = length(aws_cloudfront_distribution.this[0].default_cache_behavior[0].lambda_function_association) == 1
    error_message = "Viewer-event Lambda@Edge works with a VPC origin."
  }
}

run "disabled_creates_no_vpc_origin" {
  command = plan

  variables {
    enabled = false
    custom_origins = [{
      domain_name = "origin.app.example.com"
      origin_id   = "alb"
      vpc_origin  = { arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/test-webapp-alb/0123456789abcdef" }
    }]
  }

  assert {
    condition     = length(aws_cloudfront_vpc_origin.this) == 0 && length(terraform_data.vpc_origin) == 0 && output.vpc_origin_ids == {}
    error_message = "enabled = false creates no VPC origin."
  }
}

run "rejects_vpc_origin_with_custom_origin_config" {
  command = plan

  variables {
    custom_origins = [{
      domain_name          = "origin.app.example.com"
      origin_id            = "alb"
      custom_origin_config = { origin_read_timeout = 60 }
      vpc_origin           = { arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/test-webapp-alb/0123456789abcdef" }
    }]
  }

  expect_failures = [var.custom_origins]
}

run "rejects_target_group_arn" {
  command = plan

  variables {
    custom_origins = [{
      domain_name = "origin.app.example.com"
      origin_id   = "alb"
      vpc_origin  = { arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/test-tg/0123456789abcdef" }
    }]
  }

  expect_failures = [var.custom_origins]
}

run "rejects_gateway_load_balancer_arn" {
  command = plan

  variables {
    custom_origins = [{
      domain_name = "origin.app.example.com"
      origin_id   = "alb"
      vpc_origin  = { arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/gwy/test-gwlb/0123456789abcdef" }
    }]
  }

  expect_failures = [var.custom_origins]
}

run "rejects_vpc_origin_sslv3" {
  command = plan

  variables {
    custom_origins = [{
      domain_name = "origin.app.example.com"
      origin_id   = "alb"
      vpc_origin = {
        arn                  = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/test-webapp-alb/0123456789abcdef"
        origin_ssl_protocols = ["SSLv3", "TLSv1.2"]
      }
    }]
  }

  expect_failures = [var.custom_origins]
}

run "rejects_vpc_origin_read_timeout_over_180" {
  command = plan

  variables {
    custom_origins = [{
      domain_name = "origin.app.example.com"
      origin_id   = "alb"
      vpc_origin = {
        arn                 = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/test-webapp-alb/0123456789abcdef"
        origin_read_timeout = 181
      }
    }]
  }

  expect_failures = [var.custom_origins]
}

run "rejects_origin_request_lambda_on_vpc_default_origin" {
  command = plan

  variables {
    custom_origins = [{
      domain_name = "origin.app.example.com"
      origin_id   = "alb"
      vpc_origin  = { arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/test-webapp-alb/0123456789abcdef" }
    }]
    lambda_function_association = [{ event_type = "origin-request", lambda_arn = "arn:aws:lambda:us-east-1:123456789012:function:rewrite:1" }]
  }

  expect_failures = [var.lambda_function_association]
}

run "rejects_origin_response_lambda_in_ordered_behavior_on_vpc_origin" {
  command = plan

  variables {
    custom_origins = [
      {
        domain_name = "origin.app.example.com"
        origin_id   = "alb"
        vpc_origin  = { arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/test-webapp-alb/0123456789abcdef" }
      },
      { domain_name = "api.example.com", origin_id = "api" },
    ]
    default_origin_id = "api"
    ordered_cache = [{
      path_pattern                = "/app/*"
      target_origin_id            = "alb"
      lambda_function_association = [{ event_type = "origin-response", lambda_arn = "arn:aws:lambda:us-east-1:123456789012:function:headers:2" }]
    }]
  }

  expect_failures = [var.ordered_cache]
}
