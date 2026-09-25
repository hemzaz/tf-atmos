# Application Load Balancer, modelled on Cloud Posse's aws-alb component
# (cloudposse-terraform-components/aws-alb, wrapping cloudposse/terraform-aws-alb),
# written as plain resources like the other root components (see
# components/terraform/s3). Two differences from the Cloud Posse component,
# both owner decisions for this repo:
#
#   1. The ALB owns its own security group instead of taking caller-supplied
#      ones, and that security group admits only the CloudFront origin-facing
#      managed prefix list on 443 (plus any additional prefix lists or
#      security groups the caller names -- never a CIDR block).
#   2. There is no port 80 listener. CloudFront does the http -> https
#      redirect at the edge.

locals {
  enabled = var.enabled

  name = "${var.tags["Environment"]}-${var.name}"

  access_logs_enabled = local.enabled && var.access_logs_enabled
}

data "aws_partition" "current" {}

# ---------------------------------------------------------------------------
# Security group: HTTPS only, from the CloudFront origin-facing prefix list.
# ---------------------------------------------------------------------------

data "aws_ec2_managed_prefix_list" "cloudfront" {
  count = local.enabled ? 1 : 0
  name  = "com.amazonaws.global.cloudfront.origin-facing"
}

resource "aws_security_group" "this" {
  count = local.enabled ? 1 : 0

  name_prefix = "${local.name}-"
  description = "ALB ${local.name}: HTTPS from the CloudFront origin-facing prefix list only"
  vpc_id      = var.vpc_id

  tags = { Name = local.name }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "cloudfront" {
  count = local.enabled ? 1 : 0

  security_group_id = aws_security_group.this[0].id
  description       = "HTTPS from the CloudFront origin-facing managed prefix list"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  prefix_list_id    = data.aws_ec2_managed_prefix_list.cloudfront[0].id
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
# granting the region's ELB log-delivery account write access under its own
# prefix. `aws_elb_service_account` covers every standard AWS region
# (including this repo's eu-west-2); an opt-in region would additionally need
# the delivery.logs.amazonaws.com service principal, which is out of scope
# here.
# ---------------------------------------------------------------------------

data "aws_caller_identity" "current" {
  count = local.access_logs_enabled ? 1 : 0
}

data "aws_elb_service_account" "this" {
  count = local.access_logs_enabled ? 1 : 0
}

locals {
  access_logs_bucket_name = "${local.name}-access-logs"
  access_logs_bucket_arn  = "arn:${data.aws_partition.current.partition}:s3:::${local.access_logs_bucket_name}"
  access_logs_key_prefix  = var.access_logs_prefix != "" ? "${trim(var.access_logs_prefix, "/")}/" : ""
}

resource "aws_s3_bucket" "access_logs" {
  #checkov:skip=CKV2_AWS_6:aws_s3_bucket_public_access_block.access_logs covers this bucket via count
  #checkov:skip=CKV_AWS_21:aws_s3_bucket_versioning.access_logs covers this bucket via count
  #checkov:skip=CKV_AWS_145:ALB access log delivery only supports SSE-S3, not SSE-KMS
  #checkov:skip=CKV_AWS_18:This bucket IS the access-log destination; access logs of a log bucket are out of scope
  #checkov:skip=CKV2_AWS_61:A short-lived lifecycle rule is unnecessary for access logs sized for this repo's stacks
  #checkov:skip=CKV2_AWS_62:Event notifications are out of scope for this component
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

data "aws_iam_policy_document" "access_logs" {
  count = local.access_logs_enabled ? 1 : 0

  statement {
    sid    = "AllowELBLogDelivery"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [data.aws_elb_service_account.this[0].arn]
    }

    actions   = ["s3:PutObject"]
    resources = ["${local.access_logs_bucket_arn}/${local.access_logs_key_prefix}AWSLogs/${data.aws_caller_identity.current[0].account_id}/*"]
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

resource "aws_lb" "this" {
  #checkov:skip=CKV_AWS_150:deletion_protection is an input; stacks that want it set var.deletion_protection = true
  count = local.enabled ? 1 : 0

  name               = local.name
  internal           = var.internal
  load_balancer_type = "application"
  subnets            = var.subnets
  security_groups    = [aws_security_group.this[0].id]

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
      prefix  = var.access_logs_prefix
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
  count = local.enabled ? 1 : 0

  name        = "${local.name}-default"
  port        = var.default_target_group_port
  protocol    = var.default_target_group_protocol
  vpc_id      = var.vpc_id
  target_type = "ip"

  deregistration_delay = var.default_target_group_deregistration_delay

  health_check {
    enabled             = true
    path                = "/"
    matcher             = "200-499"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
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

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.default[0].arn
  }
}
