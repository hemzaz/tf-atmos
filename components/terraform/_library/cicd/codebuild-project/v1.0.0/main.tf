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
      Module    = "cicd/codebuild-project"
    }
  )

  # CloudWatch Logs configuration
  cloudwatch_logs_group_name = var.cloudwatch_logs_group_name != null ? var.cloudwatch_logs_group_name : "/aws/codebuild/${var.name}"

  # Environment variables with defaults
  environment_variables = [
    for env in var.environment_variables : {
      name  = env.name
      value = env.value
      type  = coalesce(env.type, "PLAINTEXT")
    }
  ]
}

################################################################################
# CloudWatch Logs Group
################################################################################

resource "aws_cloudwatch_log_group" "this" {
  count = var.enable_cloudwatch_logs ? 1 : 0

  name              = local.cloudwatch_logs_group_name
  retention_in_days = 30

  tags = local.default_tags
}

################################################################################
# IAM Role for CodeBuild
################################################################################

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "this" {
  count = var.create_role ? 1 : 0

  name                 = "${local.name_prefix}-codebuild-role"
  assume_role_policy   = data.aws_iam_policy_document.assume_role.json
  permissions_boundary = var.role_permissions_boundary

  tags = local.default_tags
}

data "aws_iam_policy_document" "this" {
  # CloudWatch Logs permissions
  dynamic "statement" {
    for_each = var.enable_cloudwatch_logs ? [1] : []
    content {
      effect = "Allow"
      actions = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      resources = [
        "arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:${local.cloudwatch_logs_group_name}",
        "arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:${local.cloudwatch_logs_group_name}:*"
      ]
    }
  }

  # S3 Logs permissions
  dynamic "statement" {
    for_each = var.enable_s3_logs && var.s3_logs_location != null ? [1] : []
    content {
      effect = "Allow"
      actions = [
        "s3:PutObject",
        "s3:GetBucketAcl",
        "s3:GetBucketLocation"
      ]
      resources = [
        "arn:${local.partition}:s3:::${var.s3_logs_location}",
        "arn:${local.partition}:s3:::${var.s3_logs_location}/*"
      ]
    }
  }

  # S3 Artifacts permissions
  dynamic "statement" {
    for_each = var.artifacts_type == "S3" && var.artifacts_location != null ? [1] : []
    content {
      effect = "Allow"
      actions = [
        "s3:PutObject",
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:GetBucketAcl",
        "s3:GetBucketLocation"
      ]
      resources = [
        "arn:${local.partition}:s3:::${var.artifacts_location}",
        "arn:${local.partition}:s3:::${var.artifacts_location}/*"
      ]
    }
  }

  # S3 Cache permissions
  dynamic "statement" {
    for_each = var.cache_type == "S3" && var.cache_location != null ? [1] : []
    content {
      effect = "Allow"
      actions = [
        "s3:PutObject",
        "s3:GetObject"
      ]
      resources = [
        "arn:${local.partition}:s3:::${var.cache_location}",
        "arn:${local.partition}:s3:::${var.cache_location}/*"
      ]
    }
  }

  # CodeCommit permissions
  dynamic "statement" {
    for_each = var.source_type == "CODECOMMIT" ? [1] : []
    content {
      effect = "Allow"
      actions = [
        "codecommit:GitPull"
      ]
      resources = [
        var.source_location
      ]
    }
  }

  # VPC permissions
  dynamic "statement" {
    for_each = var.enable_vpc_config ? [1] : []
    content {
      effect = "Allow"
      actions = [
        "ec2:CreateNetworkInterface",
        "ec2:DescribeDhcpOptions",
        "ec2:DescribeNetworkInterfaces",
        "ec2:DeleteNetworkInterface",
        "ec2:DescribeSubnets",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeVpcs"
      ]
      resources = ["*"]
    }
  }

  dynamic "statement" {
    for_each = var.enable_vpc_config ? [1] : []
    content {
      effect = "Allow"
      actions = [
        "ec2:CreateNetworkInterfacePermission"
      ]
      resources = [
        "arn:${local.partition}:ec2:${local.region}:${local.account_id}:network-interface/*"
      ]
      condition {
        test     = "StringEquals"
        variable = "ec2:Subnet"
        values = [
          for subnet_id in var.subnet_ids : "arn:${local.partition}:ec2:${local.region}:${local.account_id}:subnet/${subnet_id}"
        ]
      }
      condition {
        test     = "StringEquals"
        variable = "ec2:AuthorizedService"
        values   = ["codebuild.amazonaws.com"]
      }
    }
  }

  # ECR permissions (for Docker builds)
  dynamic "statement" {
    for_each = var.environment_privileged_mode ? [1] : []
    content {
      effect = "Allow"
      actions = [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload"
      ]
      resources = ["*"]
    }
  }

  # Secrets Manager permissions (for environment variables)
  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue"
    ]
    resources = [
      "arn:${local.partition}:secretsmanager:${local.region}:${local.account_id}:secret:*"
    ]
    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/CodeBuild"
      values   = ["true"]
    }
  }

  # SSM Parameter Store permissions (for environment variables)
  statement {
    effect = "Allow"
    actions = [
      "ssm:GetParameters"
    ]
    resources = [
      "arn:${local.partition}:ssm:${local.region}:${local.account_id}:parameter/*"
    ]
  }
}

resource "aws_iam_role_policy" "this" {
  count = var.create_role ? 1 : 0

  name   = "${local.name_prefix}-codebuild-policy"
  role   = aws_iam_role.this[0].id
  policy = data.aws_iam_policy_document.this.json
}

resource "aws_iam_role_policy_attachment" "additional" {
  count = var.create_role ? length(var.additional_policy_arns) : 0

  role       = aws_iam_role.this[0].name
  policy_arn = var.additional_policy_arns[count.index]
}

################################################################################
# CodeBuild Project
################################################################################

resource "aws_codebuild_project" "this" {
  name           = local.name_prefix
  description    = var.description
  service_role   = var.create_role ? aws_iam_role.this[0].arn : var.role_arn
  build_timeout  = var.build_timeout
  queued_timeout = var.queued_timeout

  concurrent_build_limit = var.concurrent_build_limit

  tags = local.default_tags

  # Source configuration
  source {
    type                = var.source_type
    location            = var.source_location
    buildspec           = var.source_buildspec
    git_clone_depth     = var.source_type != "CODEPIPELINE" && var.source_type != "NO_SOURCE" ? var.source_git_clone_depth : null
    insecure_ssl        = false
    report_build_status = var.source_type == "GITHUB" || var.source_type == "GITHUB_ENTERPRISE" || var.source_type == "BITBUCKET"

    dynamic "git_submodules_config" {
      for_each = var.source_git_submodules_config && var.source_type != "CODEPIPELINE" && var.source_type != "NO_SOURCE" ? [1] : []
      content {
        fetch_submodules = true
      }
    }

    dynamic "auth" {
      for_each = var.source_auth_type != null ? [1] : []
      content {
        type     = var.source_auth_type
        resource = var.source_auth_resource
      }
    }
  }

  # Secondary sources
  dynamic "secondary_sources" {
    for_each = var.secondary_sources
    content {
      type              = secondary_sources.value.type
      location          = secondary_sources.value.location
      source_identifier = secondary_sources.value.source_identifier
      git_clone_depth   = secondary_sources.value.git_clone_depth
      buildspec         = secondary_sources.value.buildspec
      insecure_ssl      = coalesce(secondary_sources.value.insecure_ssl, false)

      dynamic "git_submodules_config" {
        for_each = coalesce(secondary_sources.value.git_submodules, false) ? [1] : []
        content {
          fetch_submodules = true
        }
      }
    }
  }

  # Build environment
  environment {
    compute_type                = var.environment_compute_type
    image                       = var.environment_image
    type                        = var.environment_type
    privileged_mode             = var.environment_privileged_mode
    image_pull_credentials_type = var.environment_image_pull_credentials_type
    certificate                 = var.environment_certificate

    dynamic "environment_variable" {
      for_each = local.environment_variables
      content {
        name  = environment_variable.value.name
        value = environment_variable.value.value
        type  = environment_variable.value.type
      }
    }
  }

  # VPC configuration
  dynamic "vpc_config" {
    for_each = var.enable_vpc_config ? [1] : []
    content {
      vpc_id             = var.vpc_id
      subnets            = var.subnet_ids
      security_group_ids = var.security_group_ids
    }
  }

  # Artifacts configuration
  artifacts {
    type                   = var.artifacts_type
    location               = var.artifacts_location
    path                   = var.artifacts_path
    namespace_type         = var.artifacts_namespace_type
    packaging              = var.artifacts_packaging
    encryption_disabled    = var.artifacts_encryption_disabled
    override_artifact_name = var.artifacts_override_artifact_name
  }

  # Secondary artifacts
  dynamic "secondary_artifacts" {
    for_each = var.secondary_artifacts
    content {
      artifact_identifier = secondary_artifacts.value.artifact_identifier
      type                = secondary_artifacts.value.type
      location            = secondary_artifacts.value.location
      path                = secondary_artifacts.value.path
      namespace_type      = secondary_artifacts.value.namespace_type
      packaging           = secondary_artifacts.value.packaging
      encryption_disabled = coalesce(secondary_artifacts.value.encryption_disabled, false)
    }
  }

  # Cache configuration
  cache {
    type     = var.cache_type
    location = var.cache_type == "S3" ? var.cache_location : null
    modes    = var.cache_type == "LOCAL" ? var.cache_modes : null
  }

  # Logging configuration
  logs_config {
    dynamic "cloudwatch_logs" {
      for_each = var.enable_cloudwatch_logs ? [1] : []
      content {
        status      = "ENABLED"
        group_name  = local.cloudwatch_logs_group_name
        stream_name = var.cloudwatch_logs_stream_name
      }
    }

    dynamic "s3_logs" {
      for_each = var.enable_s3_logs ? [1] : []
      content {
        status              = "ENABLED"
        location            = "${var.s3_logs_location}/${var.name}"
        encryption_disabled = var.s3_logs_encryption_disabled
      }
    }
  }

  # Build batch configuration
  dynamic "build_batch_config" {
    for_each = var.build_batch_config != null ? [1] : []
    content {
      service_role    = var.build_batch_config.service_role
      combine_artifacts = coalesce(var.build_batch_config.combine_artifacts, false)
      timeout_in_mins = var.build_batch_config.timeout_in_mins

      dynamic "restrictions" {
        for_each = var.build_batch_config.restrictions_max_builds != null || var.build_batch_config.restrictions_compute_types != null ? [1] : []
        content {
          maximum_builds_allowed = var.build_batch_config.restrictions_max_builds
          compute_types_allowed  = var.build_batch_config.restrictions_compute_types
        }
      }
    }
  }

  # File system locations
  dynamic "file_system_locations" {
    for_each = var.file_system_locations
    content {
      identifier    = file_system_locations.value.identifier
      location      = file_system_locations.value.location
      mount_point   = file_system_locations.value.mount_point
      type          = file_system_locations.value.type
      mount_options = file_system_locations.value.mount_options
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.this,
    aws_iam_role_policy.this
  ]
}

################################################################################
# Webhook for GitHub/Bitbucket
################################################################################

resource "aws_codebuild_webhook" "this" {
  count = var.enable_webhook && (var.source_type == "GITHUB" || var.source_type == "GITHUB_ENTERPRISE" || var.source_type == "BITBUCKET") ? 1 : 0

  project_name = aws_codebuild_project.this.name
  build_type   = var.webhook_build_type

  dynamic "filter_group" {
    for_each = var.webhook_filter_groups
    content {
      dynamic "filter" {
        for_each = filter_group.value
        content {
          type                    = filter.value.type
          pattern                 = filter.value.pattern
          exclude_matched_pattern = coalesce(filter.value.exclude_matched_pattern, false)
        }
      }
    }
  }
}
