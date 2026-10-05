# Application Load Balancer, modelled on Cloud Posse's aws-alb component
# (cloudposse-terraform-components/aws-alb, wrapping cloudposse/terraform-aws-alb),
# written as plain resources like the other root components (see
# components/terraform/s3). Two differences from the Cloud Posse component,
# both owner decisions for this repo:
#
#   1. The ALB owns its own security group instead of taking caller-supplied
#      ones, and that security group admits only the CloudFront origin-facing
#      managed prefix list on 443 (cloudfront_ingress_enabled, on by default;
#      off for an ALB that is not behind CloudFront), plus any additional
#      prefix lists or security groups the caller names -- never a CIDR block.
#   2. There is no port 80 listener. CloudFront does the http -> https
#      redirect at the edge.

locals {
  enabled = var.enabled

  name = "${var.tags["Environment"]}-${var.name}"

  access_logs_enabled = local.enabled && var.access_logs_enabled

  cloudfront_ingress_enabled = local.enabled && var.cloudfront_ingress_enabled
}

data "aws_partition" "current" {}

# ---------------------------------------------------------------------------
# Security group: HTTPS only, from the CloudFront origin-facing prefix list.
# ---------------------------------------------------------------------------

data "aws_ec2_managed_prefix_list" "cloudfront" {
  count = local.cloudfront_ingress_enabled ? 1 : 0
  name  = "com.amazonaws.global.cloudfront.origin-facing"
}

resource "aws_security_group" "this" {
  #checkov:skip=CKV2_AWS_5:Attached to the load balancer (aws_lb.this[0]); checkov's graph does not follow the count index in aws_security_group.this[0].id
  count = local.enabled ? 1 : 0

  name_prefix = "${local.name}-"
  # Unchanged text with CloudFront ingress on: a new description replaces the group.
  description = var.cloudfront_ingress_enabled ? "ALB ${local.name}: HTTPS from the CloudFront origin-facing prefix list only" : "ALB ${local.name}: HTTPS from the named prefix lists and security groups only"
  vpc_id      = var.vpc_id

  tags = { Name = local.name }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "cloudfront" {
  count = local.cloudfront_ingress_enabled ? 1 : 0

  security_group_id = aws_security_group.this[0].id
  description       = "HTTPS from the CloudFront origin-facing managed prefix list"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  prefix_list_id    = data.aws_ec2_managed_prefix_list.cloudfront[0].id
}

# Route 53 health checkers, from their AWS-managed prefix list (weight 25
# against the security-group rule quota): an internet-facing ALB watched by a
# Route 53 HTTPS health check that its other rules would not admit.
data "aws_ec2_managed_prefix_list" "route53_health_checks" {
  count = local.enabled && var.route53_health_check_ingress_enabled ? 1 : 0
  name  = "com.amazonaws.${var.region}.route53-healthchecks"
}

resource "aws_vpc_security_group_ingress_rule" "route53_health_checks" {
  count = local.enabled && var.route53_health_check_ingress_enabled ? 1 : 0

  security_group_id = aws_security_group.this[0].id
  description       = "HTTPS from the Route 53 health checkers' managed prefix list"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  prefix_list_id    = data.aws_ec2_managed_prefix_list.route53_health_checks[0].id
}

resource "aws_vpc_security_group_ingress_rule" "additional_prefix_lists" {
  for_each = local.enabled ? toset(var.additional_ingress_prefix_list_ids) : toset([])

  security_group_id = aws_security_group.this[0].id
  description       = "HTTPS from additional prefix list ${each.value}"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  prefix_list_id    = each.value
}

resource "aws_vpc_security_group_ingress_rule" "additional_security_groups" {
  for_each = local.enabled ? toset(var.additional_ingress_security_group_ids) : toset([])

  security_group_id            = aws_security_group.this[0].id
  description                  = "HTTPS from additional security group ${each.value}"
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  referenced_security_group_id = each.value
}

#trivy:ignore:AVD-AWS-0104 Egress is unrestricted by policy (owner decision): the prefix-list and security-group ingress rules above cover inbound traffic; egress may be open.
resource "aws_vpc_security_group_egress_rule" "all" {
  count = local.enabled ? 1 : 0

  security_group_id = aws_security_group.this[0].id
  description       = "Allow all outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ---------------------------------------------------------------------------
# Access-logs bucket. ALB access logs only support SSE-S3, so this is a
# dedicated bucket (not the repo's SSE-KMS s3 component), following Cloud
# Posse's lb-s3-bucket: TLS-only, fully public-access-blocked, and a policy
# granting only the logdelivery.elasticloadbalancing.amazonaws.com service
# principal write access under its own prefix, scoped with an
# aws:SourceAccount condition (AWS's current recommendation for every
# region, superseding the legacy per-region aws_elb_service_account
# principal, which cannot take that condition).
# ---------------------------------------------------------------------------

data "aws_caller_identity" "current" {
  count = local.access_logs_enabled ? 1 : 0
}

locals {
  # S3 bucket names are global across all AWS accounts; the account id keeps
  # this bucket's name unique the way the repo's other component-created
  # buckets do (awsconfig/main.tf, cloudtrail/main.tf).
  access_logs_bucket_name = local.access_logs_enabled ? "${local.name}-access-logs-${data.aws_caller_identity.current[0].account_id}" : ""
  access_logs_bucket_arn  = "arn:${data.aws_partition.current.partition}:s3:::${local.access_logs_bucket_name}"
  access_logs_key_prefix  = var.access_logs_prefix != "" ? "${trim(var.access_logs_prefix, "/")}/" : ""
}

resource "aws_s3_bucket" "access_logs" {
  #checkov:skip=CKV2_AWS_6:aws_s3_bucket_public_access_block.access_logs covers this bucket via count
  #checkov:skip=CKV_AWS_21:aws_s3_bucket_versioning.access_logs covers this bucket via count
  #checkov:skip=CKV_AWS_145:ALB access log delivery only supports SSE-S3, not SSE-KMS
  #checkov:skip=CKV_AWS_18:This bucket IS the access-log destination; access logs of a log bucket are out of scope
  #checkov:skip=CKV2_AWS_61:aws_s3_bucket_lifecycle_configuration.access_logs covers this bucket via count when lifecycle_rule_enabled is set
  #checkov:skip=CKV2_AWS_62:Event notifications are out of scope for this component
  #checkov:skip=CKV_AWS_144:Access-log bucket; cross-region replication is out of scope for this component (mirrors s3/main.tf and cloudtrail/main.tf)
  count = local.access_logs_enabled ? 1 : 0

  bucket        = local.access_logs_bucket_name
  force_destroy = var.access_logs_force_destroy

  tags = { Name = local.access_logs_bucket_name }
}

resource "aws_s3_bucket_public_access_block" "access_logs" {
  count = local.access_logs_enabled ? 1 : 0

  bucket = aws_s3_bucket.access_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "access_logs" {
  count = local.access_logs_enabled ? 1 : 0

  bucket = aws_s3_bucket.access_logs[0].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

#trivy:ignore:AVD-AWS-0132 ALB access log delivery only supports SSE-S3, not a customer-managed KMS key (see s3-backend.tf's equivalent skip)
resource "aws_s3_bucket_server_side_encryption_configuration" "access_logs" {
  count = local.access_logs_enabled ? 1 : 0

  bucket = aws_s3_bucket.access_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "access_logs" {
  count = local.access_logs_enabled ? 1 : 0

  bucket = aws_s3_bucket.access_logs[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

# Cloud Posse lb-s3-bucket's lifecycle: expire the logs (and their
# noncurrent versions) after expiration_days / noncurrent_version_expiration_days,
# and abort incomplete multipart uploads. Off by default, as upstream.
resource "aws_s3_bucket_lifecycle_configuration" "access_logs" {
  count = local.access_logs_enabled && var.lifecycle_rule_enabled ? 1 : 0

  bucket = aws_s3_bucket.access_logs[0].id

  rule {
    id     = "expire-access-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = var.expiration_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiration_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = var.abort_incomplete_multipart_upload_days
    }
  }
}

data "aws_iam_policy_document" "access_logs" {
  count = local.access_logs_enabled ? 1 : 0

  statement {
    sid    = "AllowELBLogDelivery"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["logdelivery.elasticloadbalancing.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${local.access_logs_bucket_arn}/${local.access_logs_key_prefix}AWSLogs/${data.aws_caller_identity.current[0].account_id}/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current[0].account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.current.partition}:elasticloadbalancing:${var.region}:${data.aws_caller_identity.current[0].account_id}:loadbalancer/*"]
    }
  }

  statement {
    sid       = "ForceSSLOnlyAccess"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [local.access_logs_bucket_arn, "${local.access_logs_bucket_arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "access_logs" {
  count = local.access_logs_enabled ? 1 : 0

  bucket = aws_s3_bucket.access_logs[0].id
  policy = data.aws_iam_policy_document.access_logs[0].json

  depends_on = [aws_s3_bucket_public_access_block.access_logs]
}

# ---------------------------------------------------------------------------
# Load balancer, default target group and HTTPS listener.
# ---------------------------------------------------------------------------

#trivy:ignore:AVD-AWS-0053 Internet-facing by design (owner decision): the security groups admit 443 only from the CloudFront origin-facing prefix list and the named prefix lists and security groups, never 0.0.0.0/0.
resource "aws_lb" "this" {
  #checkov:skip=CKV_AWS_150:deletion_protection is an input; stacks that want it set var.deletion_protection = true
  #checkov:skip=CKV2_AWS_28:False positive; the waf component associates a REGIONAL web ACL with this ALB's alb_arn output (see stacks/catalog/templates/web-application.yaml web-application/waf) -- checkov's graph does not follow that cross-component association
  count = local.enabled ? 1 : 0

  name               = local.name
  internal           = var.internal
  load_balancer_type = "application"
  subnets            = var.subnets
  security_groups    = concat([aws_security_group.this[0].id], var.security_group_ids)

  idle_timeout                     = var.idle_timeout
  enable_deletion_protection       = var.deletion_protection
  drop_invalid_header_fields       = var.drop_invalid_header_fields
  desync_mitigation_mode           = var.desync_mitigation_mode
  enable_http2                     = var.enable_http2
  enable_cross_zone_load_balancing = true

  dynamic "access_logs" {
    for_each = local.access_logs_enabled ? [1] : []
    content {
      bucket  = aws_s3_bucket.access_logs[0].id
      prefix  = trim(var.access_logs_prefix, "/")
      enabled = true
    }
  }

  tags = { Name = local.name }

  lifecycle {
    precondition {
      condition     = length(local.name) <= 32
      error_message = "The load balancer name (currently \"${local.name}\", ${length(local.name)} characters) must be 32 characters or fewer. Shorten name or Environment."
    }
  }

  depends_on = [aws_s3_bucket_policy.access_logs]
}

resource "aws_lb_target_group" "default" {
  #checkov:skip=CKV_AWS_378:TLS terminates at the ALB's HTTPS listener (443); targets are reached over plain HTTP inside the VPC, the default_target_group_protocol default
  count = local.enabled ? 1 : 0

  name        = "${local.name}-default"
  port        = var.default_target_group_port
  protocol    = var.default_target_group_protocol
  vpc_id      = var.vpc_id
  target_type = "ip"

  deregistration_delay = var.default_target_group_deregistration_delay

  health_check {
    enabled             = true
    path                = var.health_check_path
    matcher             = var.health_check_matcher
    healthy_threshold   = var.health_check_healthy_threshold
    unhealthy_threshold = var.health_check_unhealthy_threshold
    timeout             = var.health_check_timeout
    interval            = var.health_check_interval
  }

  tags = { Name = "${local.name}-default" }

  lifecycle {
    precondition {
      condition     = length("${local.name}-default") <= 32
      error_message = "The default target group name (currently \"${local.name}-default\", ${length("${local.name}-default")} characters) must be 32 characters or fewer. Shorten name or Environment."
    }
  }
}

resource "aws_lb_listener" "https" {
  count = local.enabled ? 1 : 0

  load_balancer_arn = aws_lb.this[0].arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = var.ssl_policy
  certificate_arn   = var.certificate_arn

  # Forward to the default target group, or (listener_https_fixed_response)
  # answer every request no listener rule matched with a fixed response.
  default_action {
    type             = var.listener_https_fixed_response == null ? "forward" : "fixed-response"
    target_group_arn = var.listener_https_fixed_response == null ? aws_lb_target_group.default[0].arn : null

    dynamic "fixed_response" {
      for_each = var.listener_https_fixed_response == null ? [] : [var.listener_https_fixed_response]
      content {
        content_type = fixed_response.value.content_type
        message_body = fixed_response.value.message_body
        status_code  = fixed_response.value.status_code
      }
    }
  }
}

# ---------------------------------------------------------------------------
# Route 53 alias records (dns_alias_enabled): A records to the load balancer,
# as Cloud Posse's terraform-aws-route53-alias does for its callers.
# ---------------------------------------------------------------------------

resource "aws_route53_record" "alias" {
  for_each = local.enabled && var.dns_alias_enabled ? toset(var.dns_aliases) : toset([])

  zone_id = var.parent_zone_id
  name    = each.value
  type    = "A"

  alias {
    name                   = aws_lb.this[0].dns_name
    zone_id                = aws_lb.this[0].zone_id
    evaluate_target_health = true
  }
}
