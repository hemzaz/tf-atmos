################################################################################
# Data Sources
################################################################################

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

################################################################################
# Locals
################################################################################

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
  partition  = data.aws_partition.current.partition

  name_prefix = var.name

  default_tags = merge(
    var.tags,
    {
      ManagedBy = "Terraform"
      Module    = "cicd/ecr-repository"
    }
  )

  # Default lifecycle policy
  default_lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Remove untagged images after ${var.untagged_image_retention_days} days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_image_retention_days
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Keep only ${var.tagged_image_count_limit} tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v", "release"]
          countType     = "imageCountMoreThan"
          countNumber   = var.tagged_image_count_limit
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 3
        description  = "Keep only ${var.tagged_image_count_limit} any tagged images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.tagged_image_count_limit * 2
        }
        action = {
          type = "expire"
        }
      }
    ]
  })

  # Repository policy for cross-account access
  has_cross_account_access = length(var.cross_account_principals) > 0

  default_repository_policy = local.has_cross_account_access ? jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCrossAccountPull"
        Effect = "Allow"
        Principal = {
          AWS = var.cross_account_principals
        }
        Action = var.cross_account_actions
      }
    ]
  }) : null
}

################################################################################
# ECR Repository
################################################################################

resource "aws_ecr_repository" "this" {
  name                 = local.name_prefix
  image_tag_mutability = var.image_tag_mutability
  force_delete         = var.force_delete

  tags = local.default_tags

  # Image scanning configuration
  image_scanning_configuration {
    scan_on_push = var.enable_scan_on_push
  }

  # Encryption configuration
  encryption_configuration {
    encryption_type = var.encryption_type
    kms_key         = var.kms_key_id
  }
}

################################################################################
# Registry Scanning Configuration (Enhanced Scanning)
################################################################################

resource "aws_ecr_registry_scanning_configuration" "this" {
  count = var.scan_type == "ENHANCED" ? 1 : 0

  scan_type = var.scan_type

  rule {
    scan_frequency = var.scan_frequency

    repository_filter {
      filter      = var.name
      filter_type = "WILDCARD"
    }
  }
}

################################################################################
# Lifecycle Policy
################################################################################

resource "aws_ecr_lifecycle_policy" "this" {
  count = var.enable_lifecycle_policy ? 1 : 0

  repository = aws_ecr_repository.this.name
  policy     = var.lifecycle_policy_rules != null ? var.lifecycle_policy_rules : local.default_lifecycle_policy
}

################################################################################
# Repository Policy
################################################################################

resource "aws_ecr_repository_policy" "this" {
  count = var.repository_policy != null || local.has_cross_account_access ? 1 : 0

  repository = aws_ecr_repository.this.name
  policy     = var.repository_policy != null ? var.repository_policy : local.default_repository_policy
}

################################################################################
# Replication Configuration
################################################################################

resource "aws_ecr_replication_configuration" "this" {
  count = var.enable_replication && length(var.replication_destinations) > 0 ? 1 : 0

  replication_configuration {
    rule {
      dynamic "destination" {
        for_each = var.replication_destinations
        content {
          region      = destination.value.region
          registry_id = destination.value.registry_id != null ? destination.value.registry_id : local.account_id
        }
      }

      dynamic "repository_filter" {
        for_each = length(var.replication_filters) > 0 ? var.replication_filters : [
          {
            filter      = var.name
            filter_type = "PREFIX_MATCH"
          }
        ]
        content {
          filter      = repository_filter.value.filter
          filter_type = repository_filter.value.filter_type
        }
      }
    }
  }
}

################################################################################
# Pull Through Cache Rule
################################################################################

resource "aws_ecr_pull_through_cache_rule" "this" {
  count = var.enable_pull_through_cache && var.upstream_registry_url != null ? 1 : 0

  ecr_repository_prefix = local.name_prefix
  upstream_registry_url = var.upstream_registry_url
  credential_arn        = var.credential_arn
}

################################################################################
# CloudWatch Log Group for Metrics
################################################################################

resource "aws_cloudwatch_log_group" "this" {
  count = var.enable_cloudwatch_metrics ? 1 : 0

  name              = "/aws/ecr/${var.name}"
  retention_in_days = 30

  tags = local.default_tags
}

################################################################################
# CloudWatch Metric Alarms
################################################################################

resource "aws_cloudwatch_metric_alarm" "image_scan_findings_high" {
  count = var.enable_cloudwatch_metrics && var.enable_scan_on_push ? 1 : 0

  alarm_name          = "${local.name_prefix}-high-severity-findings"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "ImageScanFindingsSeverityCritical"
  namespace           = "AWS/ECR"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "Alert when high severity vulnerabilities are found in ${var.name}"
  treat_missing_data  = "notBreaching"

  dimensions = {
    RepositoryName = aws_ecr_repository.this.name
  }

  tags = local.default_tags
}

resource "aws_cloudwatch_metric_alarm" "repository_pull_count" {
  count = var.enable_cloudwatch_metrics ? 1 : 0

  alarm_name          = "${local.name_prefix}-low-pull-count"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "7"
  metric_name         = "RepositoryPullCount"
  namespace           = "AWS/ECR"
  period              = "86400"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "Alert when repository ${var.name} has no pulls for 7 days (potentially unused)"
  treat_missing_data  = "notBreaching"

  dimensions = {
    RepositoryName = aws_ecr_repository.this.name
  }

  tags = local.default_tags
}
