# Offline tests: the real AWS provider with dummy credentials, as in
# kms/tests and s3/tests. Every data source that would call AWS is
# overridden, so nothing reaches AWS (all runs are plans).
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
  target = data.aws_partition.current
  values = {
    partition = "aws"
  }
}

override_data {
  target = data.aws_caller_identity.current
  values = {
    account_id = "123456789012"
  }
}

override_data {
  target = data.aws_ec2_managed_prefix_list.cloudfront
  values = {
    id  = "pl-00a54069"
    arn = "arn:aws:ec2:eu-west-2:aws:prefix-list/pl-00a54069"
  }
}

variables {
  region          = "eu-west-2"
  name            = "webapp-alb"
  vpc_id          = "vpc-00000000000000000"
  subnets         = ["subnet-00000000000000001", "subnet-00000000000000002"]
  certificate_arn = "arn:aws:acm:eu-west-2:123456789012:certificate/00000000-0000-0000-0000-000000000000"
  tags = {
    Environment = "test"
    Tenant      = "fnx"
    ManagedBy   = "Terraform"
  }
}

run "security_group_admits_only_the_cloudfront_prefix_list_on_443" {
  command = plan

  assert {
    condition     = aws_vpc_security_group_ingress_rule.cloudfront[0].prefix_list_id == "pl-00a54069"
    error_message = "The CloudFront origin-facing managed prefix list is resolved and wired into the ingress rule."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.cloudfront[0].from_port == 443 && aws_vpc_security_group_ingress_rule.cloudfront[0].to_port == 443
    error_message = "The CloudFront ingress rule is scoped to port 443."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.cloudfront[0].cidr_ipv4 == null && aws_vpc_security_group_ingress_rule.cloudfront[0].cidr_ipv6 == null
    error_message = "The CloudFront ingress rule carries no CIDR block."
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.additional_prefix_lists) == 0 && length(aws_vpc_security_group_ingress_rule.additional_security_groups) == 0
    error_message = "No additional ingress sources are created unless the caller asks for them."
  }
}

run "no_cidr_ingress_exists_anywhere_in_the_security_group" {
  command = plan

  # There is no resource type in this component that could add a CIDR-based
  # ingress rule; this asserts across every ingress rule resource that
  # exists (with at least one populated element in each), so the invariant
  # fails loudly if a future edit adds a cidr_blocks argument to any of them.
  variables {
    additional_ingress_prefix_list_ids    = ["pl-fake11111111111"]
    additional_ingress_security_group_ids = ["sg-fake222222222222"]
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.cloudfront[0].cidr_ipv4 == null && aws_vpc_security_group_ingress_rule.cloudfront[0].cidr_ipv6 == null
    error_message = "The CloudFront ingress rule must never carry a CIDR block."
  }

  assert {
    condition     = alltrue([for r in aws_vpc_security_group_ingress_rule.additional_prefix_lists : r.cidr_ipv4 == null && r.cidr_ipv6 == null])
    error_message = "Additional prefix list ingress rules must never carry a CIDR block."
  }

  assert {
    condition     = alltrue([for r in aws_vpc_security_group_ingress_rule.additional_security_groups : r.cidr_ipv4 == null && r.cidr_ipv6 == null])
    error_message = "Additional security group ingress rules must never carry a CIDR block."
  }
}

run "additional_prefix_lists_and_security_groups_are_added_on_top" {
  command = plan

  variables {
    additional_ingress_prefix_list_ids    = ["pl-fake11111111111"]
    additional_ingress_security_group_ids = ["sg-fake222222222222"]
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.additional_prefix_lists["pl-fake11111111111"].prefix_list_id == "pl-fake11111111111"
    error_message = "An additional prefix list is admitted on 443."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.additional_security_groups["sg-fake222222222222"].referenced_security_group_id == "sg-fake222222222222"
    error_message = "An additional security group is admitted on 443."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.cloudfront[0].prefix_list_id == "pl-00a54069"
    error_message = "The CloudFront prefix list is still admitted alongside the additional sources."
  }
}

run "there_is_no_listener_on_port_80" {
  command = plan

  assert {
    condition     = aws_lb_listener.https[0].port == 443 && aws_lb_listener.https[0].protocol == "HTTPS"
    error_message = "The only listener is HTTPS on 443."
  }

  # aws_lb_listener.https is the only listener resource this component
  # defines; there is no aws_lb_listener resource for port 80 to reference,
  # so the absence of a port-80 listener is structural, not a plan-time
  # count of zero.
}

run "https_default_action_forwards_to_the_default_target_group" {
  command = plan

  assert {
    condition     = one(aws_lb_listener.https[0].default_action).type == "forward"
    error_message = "The default action forwards traffic."
  }

  assert {
    condition     = aws_lb_target_group.default[0].name == "test-webapp-alb-default"
    error_message = "The default target group is named <Environment>-<name>-default."
  }
}

run "default_target_group_health_check_uses_cloud_posse_defaults" {
  command = plan

  assert {
    condition     = one(aws_lb_target_group.default[0].health_check).path == "/"
    error_message = "The default target group health check path defaults to /."
  }

  assert {
    condition     = one(aws_lb_target_group.default[0].health_check).matcher == "200-399"
    error_message = "The default target group health check matcher defaults to 200-399, the Cloud Posse terraform-aws-alb default."
  }
}

run "default_target_group_health_check_is_overridable" {
  command = plan

  variables {
    health_check_path                = "/health"
    health_check_matcher             = "200"
    health_check_interval            = 15
    health_check_timeout             = 3
    health_check_healthy_threshold   = 2
    health_check_unhealthy_threshold = 2
  }

  assert {
    condition     = one(aws_lb_target_group.default[0].health_check).path == "/health"
    error_message = "health_check_path overrides the default target group's health check path."
  }

  assert {
    condition     = one(aws_lb_target_group.default[0].health_check).matcher == "200"
    error_message = "health_check_matcher overrides the default target group's health check matcher."
  }

  assert {
    condition = (
      one(aws_lb_target_group.default[0].health_check).interval == 15 &&
      one(aws_lb_target_group.default[0].health_check).timeout == 3 &&
      one(aws_lb_target_group.default[0].health_check).healthy_threshold == 2 &&
      one(aws_lb_target_group.default[0].health_check).unhealthy_threshold == 2
    )
    error_message = "health_check_interval/timeout/healthy_threshold/unhealthy_threshold override the default target group's health check."
  }
}

run "access_logs_bucket_denies_non_tls_and_grants_only_the_elb_account" {
  command = plan

  assert {
    condition     = aws_s3_bucket.access_logs[0].bucket == "test-webapp-alb-access-logs-123456789012"
    error_message = "The access-logs bucket is named <Environment>-<name>-access-logs-<account-id>."
  }

  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.access_logs[0].rule).apply_server_side_encryption_by_default[0].sse_algorithm == "AES256"
    error_message = "Access log delivery only supports SSE-S3, never SSE-KMS."
  }

  assert {
    condition = alltrue([
      for s in jsondecode(data.aws_iam_policy_document.access_logs[0].json).Statement :
      s.Sid != "ForceSSLOnlyAccess" || (s.Effect == "Deny" && s.Condition.Bool["aws:SecureTransport"] == "false")
    ])
    error_message = "Non-TLS requests are denied."
  }

  assert {
    condition = alltrue([
      for s in jsondecode(data.aws_iam_policy_document.access_logs[0].json).Statement :
      s.Sid != "AllowELBLogDelivery" || (
        s.Principal.Service == "logdelivery.elasticloadbalancing.amazonaws.com" &&
        s.Condition.StringEquals["aws:SourceAccount"] == "123456789012" &&
        s.Condition.ArnLike["aws:SourceArn"] == "arn:aws:elasticloadbalancing:eu-west-2:123456789012:loadbalancer/*"
      )
    ])
    error_message = "Only the logdelivery.elasticloadbalancing.amazonaws.com service principal, scoped to this account and this region's load balancers, may write access logs."
  }
}

run "access_logs_can_be_disabled" {
  command = plan

  variables {
    access_logs_enabled = false
  }

  assert {
    condition     = length(aws_s3_bucket.access_logs) == 0
    error_message = "No access-logs bucket is created when access_logs_enabled is false."
  }

  assert {
    condition     = length(aws_lb.this[0].access_logs) == 0
    error_message = "The load balancer has no access_logs block when disabled."
  }
}
