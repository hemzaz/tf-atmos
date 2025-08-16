# Data sources for IDP Platform Infrastructure Component

# VPC and networking data
data "aws_vpc" "selected" {
  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.selected.id]
  }

  tags = {
    Type = "private"
  }
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.selected.id]
  }

  tags = {
    Type = "public"
  }
}

# Availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# Current AWS region
data "aws_region" "current" {}

# Current AWS caller identity
data "aws_caller_identity" "current" {}

# AMI for EKS worker nodes
data "aws_ami" "eks_worker" {
  filter {
    name   = "name"
    values = ["amazon-eks-node-${var.cluster_version}-v*"]
  }

  most_recent = true
  owners      = ["602401143452"] # Amazon EKS AMI Account ID
}

# Route53 hosted zone (if existing)
data "aws_route53_zone" "parent" {
  count = length(split(".", var.domain_name)) > 2 ? 1 : 0

  name         = join(".", slice(split(".", var.domain_name), 1, length(split(".", var.domain_name))))
  private_zone = false
}

# IAM policy documents
data "aws_iam_policy_document" "rds_enhanced_monitoring" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "alb_logs" {
  statement {
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [data.aws_elb_service_account.main.arn]
    }

    actions   = ["s3:PutObject"]
    resources = ["${module.idp_storage["logs"].bucket_arn}/alb-access-logs/*"]
  }

  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${module.idp_storage["logs"].bucket_arn}/alb-access-logs/*"]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }

  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    actions   = ["s3:GetBucketAcl"]
    resources = [module.idp_storage["logs"].bucket_arn]
  }
}

# ELB service account for ALB access logs
data "aws_elb_service_account" "main" {}

# ECR repositories for container images
data "aws_ecr_repository" "backstage" {
  name = "idp-backstage"
}

data "aws_ecr_repository" "platform_api" {
  name = "idp-platform-api"
}

# SSM parameters for configuration
data "aws_ssm_parameter" "github_token" {
  count = var.enable_github_integration ? 1 : 0
  name  = "/${local.name_prefix}/github/token"
}

data "aws_ssm_parameter" "slack_webhook" {
  count = var.notification_endpoints.slack != "" ? 1 : 0
  name  = "/${local.name_prefix}/slack/webhook"
}

# Existing KMS keys
data "aws_kms_key" "ebs" {
  key_id = "alias/aws/ebs"
}

data "aws_kms_key" "rds" {
  key_id = "alias/aws/rds"
}

data "aws_kms_key" "secretsmanager" {
  key_id = "alias/aws/secretsmanager"
}

# Default tags from context
data "aws_default_tags" "current" {}

# Partition for cross-region support
data "aws_partition" "current" {}

# Certificate validation records (if using DNS validation)
data "aws_route53_record" "cert_validation" {
  count = var.domain_name != "" ? 1 : 0

  zone_id = aws_route53_zone.main.zone_id
  name    = tolist(module.acm_certificate.domain_validation_options)[0].resource_record_name
  type    = tolist(module.acm_certificate.domain_validation_options)[0].resource_record_type
}

# Existing security groups (if any)
data "aws_security_groups" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.selected.id]
  }

  filter {
    name   = "group-name"
    values = ["default"]
  }
}