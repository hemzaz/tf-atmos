# Security module - Standardized security patterns and KMS key management
# This module provides reusable security components across all infrastructure

# Import common module for standardized naming and tagging
module "common" {
  source = "../common"
  
  namespace               = var.namespace
  environment            = var.environment
  stage                  = var.stage
  component_name         = var.component_name
  region                 = var.region
  project_name           = var.project_name
  cost_center            = var.cost_center
  owner                  = var.owner
  additional_tags        = var.additional_tags
  data_classification    = var.data_classification
  compliance_frameworks  = var.compliance_frameworks
  backup_required        = var.backup_required
}

# KMS key for encryption at rest
resource "aws_kms_key" "main" {
  count = var.create_kms_key ? 1 : 0
  
  description              = "KMS key for ${module.common.component_name}"
  key_usage               = var.kms_key_usage
  customer_master_key_spec = var.kms_key_spec
  deletion_window_in_days = var.kms_key_deletion_window
  enable_key_rotation     = var.enable_key_rotation
  multi_region            = var.enable_multi_region_key

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        # Root user permissions
        {
          Sid    = "EnableRootUserPermissions"
          Effect = "Allow"
          Principal = {
            AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"
          }
          Action   = "kms:*"
          Resource = "*"
        }
      ],
      # Service-specific permissions
      var.enable_s3_permissions ? [{
        Sid    = "AllowS3Service"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:CallerAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }] : [],
      var.enable_rds_permissions ? [{
        Sid    = "AllowRDSService"
        Effect = "Allow"
        Principal = {
          Service = "rds.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:CallerAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }] : [],
      var.enable_eks_permissions ? [{
        Sid    = "AllowEKSService"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:CallerAccount" = data.aws_caller_identity.current.account_id,
            "kms:ViaService"    = "eks.${data.aws_region.current.name}.amazonaws.com"
          }
        }
      }] : [],
      # Custom policy statements
      var.additional_kms_policy_statements
    )
  })

  tags = merge(
    module.common.common_tags,
    {
      Name        = "${module.common.component_name}-kms-key"
      Purpose     = var.kms_key_purpose
      KeyUsage    = var.kms_key_usage
    }
  )
  
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_alias" "main" {
  count = var.create_kms_key ? 1 : 0
  
  name          = "alias/${module.common.dns_name}-${var.kms_key_purpose}"
  target_key_id = aws_kms_key.main[0].key_id
}

# Security Group with standardized rules
resource "aws_security_group" "main" {
  count = var.create_security_group ? 1 : 0
  
  name        = "${module.common.component_name}-sg"
  description = var.security_group_description
  vpc_id      = var.vpc_id

  # Dynamic ingress rules
  dynamic "ingress" {
    for_each = var.ingress_rules
    content {
      description     = ingress.value.description
      from_port       = ingress.value.from_port
      to_port         = ingress.value.to_port
      protocol        = ingress.value.protocol
      cidr_blocks     = lookup(ingress.value, "cidr_blocks", [])
      ipv6_cidr_blocks = lookup(ingress.value, "ipv6_cidr_blocks", [])
      prefix_list_ids = lookup(ingress.value, "prefix_list_ids", [])
      security_groups = lookup(ingress.value, "security_groups", [])
      self            = lookup(ingress.value, "self", false)
    }
  }

  # Dynamic egress rules
  dynamic "egress" {
    for_each = var.egress_rules
    content {
      description     = egress.value.description
      from_port       = egress.value.from_port
      to_port         = egress.value.to_port
      protocol        = egress.value.protocol
      cidr_blocks     = lookup(egress.value, "cidr_blocks", [])
      ipv6_cidr_blocks = lookup(egress.value, "ipv6_cidr_blocks", [])
      prefix_list_ids = lookup(egress.value, "prefix_list_ids", [])
      security_groups = lookup(egress.value, "security_groups", [])
      self            = lookup(egress.value, "self", false)
    }
  }

  tags = merge(
    module.common.common_tags,
    {
      Name = "${module.common.component_name}-sg"
      Type = "SecurityGroup"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# IAM role for common service permissions
resource "aws_iam_role" "service_role" {
  count = var.create_service_role ? 1 : 0
  
  name = "${module.common.component_name}-service-role"
  path = var.iam_path
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        for service in var.trusted_services : {
          Effect = "Allow"
          Principal = {
            Service = service
          }
          Action = "sts:AssumeRole"
        }
      ],
      [
        for principal in var.trusted_principals : {
          Effect = "Allow"
          Principal = {
            AWS = principal
          }
          Action = "sts:AssumeRole"
        }
      ]
    )
  })

  managed_policy_arns = var.managed_policy_arns
  max_session_duration = var.max_session_duration
  
  tags = merge(
    module.common.common_tags,
    {
      Name = "${module.common.component_name}-service-role"
      Type = "ServiceRole"
    }
  )
}

# Custom IAM policy for specific permissions
resource "aws_iam_policy" "custom" {
  count = var.create_custom_policy && length(var.custom_policy_statements) > 0 ? 1 : 0
  
  name        = "${module.common.component_name}-custom-policy"
  path        = var.iam_path
  description = "Custom policy for ${module.common.component_name}"

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = var.custom_policy_statements
  })

  tags = merge(
    module.common.common_tags,
    {
      Name = "${module.common.component_name}-custom-policy"
      Type = "CustomPolicy"
    }
  )
}

# Attach custom policy to service role
resource "aws_iam_role_policy_attachment" "custom" {
  count = var.create_service_role && var.create_custom_policy && length(var.custom_policy_statements) > 0 ? 1 : 0
  
  role       = aws_iam_role.service_role[0].name
  policy_arn = aws_iam_policy.custom[0].arn
}

# CloudWatch Log Group for security-related logs
resource "aws_cloudwatch_log_group" "security_logs" {
  count = var.create_log_group ? 1 : 0
  
  name              = "/aws/${var.log_group_prefix}/${module.common.component_name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.create_kms_key ? aws_kms_key.main[0].arn : var.existing_kms_key_arn

  tags = merge(
    module.common.common_tags,
    {
      Name = "${module.common.component_name}-security-logs"
      Type = "LogGroup"
    }
  )
}

# S3 bucket policy for secure access patterns
data "aws_iam_policy_document" "s3_bucket_policy" {
  count = var.create_s3_bucket_policy ? 1 : 0

  # Deny insecure connections
  statement {
    sid       = "DenyInsecureConnections"
    effect    = "Deny"
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions = ["s3:*"]
    resources = [
      "arn:${data.aws_partition.current.partition}:s3:::${var.s3_bucket_name}",
      "arn:${data.aws_partition.current.partition}:s3:::${var.s3_bucket_name}/*"
    ]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  # Enforce encryption in transit
  statement {
    sid    = "DenyUnencryptedObjectUploads"
    effect = "Deny"
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions = ["s3:PutObject"]
    resources = [
      "arn:${data.aws_partition.current.partition}:s3:::${var.s3_bucket_name}/*"
    ]
    condition {
      test     = "StringNotEquals"
      variable = "s3:x-amz-server-side-encryption"
      values   = ["AES256", "aws:kms"]
    }
  }

  # Cross-account access restrictions
  dynamic "statement" {
    for_each = var.deny_cross_account_access ? [1] : []
    content {
      sid    = "DenyCrossAccountAccess"
      effect = "Deny"
      principals {
        type        = "*"
        identifiers = ["*"]
      }
      actions = ["s3:*"]
      resources = [
        "arn:${data.aws_partition.current.partition}:s3:::${var.s3_bucket_name}",
        "arn:${data.aws_partition.current.partition}:s3:::${var.s3_bucket_name}/*"
      ]
      condition {
        test     = "StringNotEquals"
        variable = "aws:PrincipalAccount"
        values   = [data.aws_caller_identity.current.account_id]
      }
    }
  }
}

# WAF Web ACL for application protection
resource "aws_wafv2_web_acl" "main" {
  count = var.create_waf_web_acl ? 1 : 0
  
  name  = "${module.common.component_name}-waf"
  description = "WAF Web ACL for ${module.common.component_name}"
  scope = var.waf_scope

  default_action {
    allow {}
  }

  # AWS Managed Core Rule Set
  rule {
    name     = "AWS-AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${module.common.component_name}-CommonRuleSetMetric"
      sampled_requests_enabled   = true
    }
  }

  # Rate limiting rule
  dynamic "rule" {
    for_each = var.enable_rate_limiting ? [1] : []
    content {
      name     = "RateLimitRule"
      priority = 2

      action {
        block {}
      }

      statement {
        rate_based_statement {
          limit              = var.rate_limit_per_5min
          aggregate_key_type = "IP"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${module.common.component_name}-RateLimitMetric"
        sampled_requests_enabled   = true
      }
    }
  }

  # Geo-blocking rule
  dynamic "rule" {
    for_each = length(var.blocked_countries) > 0 ? [1] : []
    content {
      name     = "GeoBlockRule"
      priority = 3

      action {
        block {}
      }

      statement {
        geo_match_statement {
          country_codes = var.blocked_countries
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${module.common.component_name}-GeoBlockMetric"
        sampled_requests_enabled   = true
      }
    }
  }

  tags = merge(
    module.common.common_tags,
    {
      Name = "${module.common.component_name}-waf"
      Type = "WebACL"
    }
  )

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${module.common.component_name}-WAFMetric"
    sampled_requests_enabled   = true
  }
}

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}