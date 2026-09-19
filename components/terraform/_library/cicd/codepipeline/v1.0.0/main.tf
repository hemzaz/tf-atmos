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
  region     = data.aws_region.current.region
  partition  = data.aws_partition.current.partition

  name_prefix = var.name

  default_tags = merge(
    var.tags,
    {
      ManagedBy = "Terraform"
      Module    = "cicd/codepipeline"
    }
  )

  # Defaults are applied through optional() attributes in the variable type.
  source_config = var.source_configuration

  # GitHub sources use CodeStar/CodeConnections (ConnectionArn + FullRepositoryId).
  source_action_provider = var.source_provider == "GitHub" ? "CodeStarSourceConnection" : var.source_provider

  # Per-provider action configuration. Every value is a string (the action
  # configuration is map(string)); nulls are dropped below.
  source_action_configurations = {
    CodeCommit = {
      RepositoryName       = local.source_config.repository_name
      BranchName           = local.source_config.branch_name
      PollForSourceChanges = tostring(local.source_config.poll_for_changes)
    }
    GitHub = {
      ConnectionArn    = local.source_config.connection_arn
      FullRepositoryId = local.source_config.repository_name
      BranchName       = local.source_config.branch_name
      DetectChanges    = tostring(local.source_config.detect_changes)
    }
    S3 = {
      S3Bucket             = local.source_config.bucket_name
      S3ObjectKey          = local.source_config.object_key
      PollForSourceChanges = tostring(local.source_config.poll_for_changes)
    }
    ECR = {
      RepositoryName = local.source_config.repository_name_ecr
      ImageTag       = local.source_config.image_tag
    }
  }
  source_action_configuration = {
    for k, v in local.source_action_configurations[var.source_provider] : k => v if v != null
  }

  deploy_action_configurations = {
    CodeDeploy = {
      ApplicationName     = var.deploy_configuration.application_name
      DeploymentGroupName = var.deploy_configuration.deployment_group
    }
    ECS = {
      ClusterName = var.deploy_configuration.cluster_name
      ServiceName = var.deploy_configuration.service_name
      FileName    = var.deploy_configuration.file_name
    }
    Lambda = {
      FunctionName = var.deploy_configuration.function_name
    }
    CloudFormation = {
      ActionMode         = "CREATE_UPDATE"
      StackName          = var.deploy_configuration.stack_name
      TemplatePath       = var.deploy_configuration.template_path
      Capabilities       = join(",", var.deploy_configuration.capabilities)
      RoleArn            = var.deploy_configuration.role_arn
      ParameterOverrides = var.deploy_configuration.parameter_overrides != null ? jsonencode(var.deploy_configuration.parameter_overrides) : null
    }
    S3 = {
      BucketName = var.deploy_configuration.bucket_name
      Extract    = tostring(var.deploy_configuration.extract)
      ObjectKey  = var.deploy_configuration.object_key
    }
  }
  deploy_action_configuration = {
    for k, v in local.deploy_action_configurations[var.deploy_provider] : k => v if v != null
  }

  build_action_configuration = {
    for k, v in {
      ProjectName          = var.build_project_name
      EnvironmentVariables = length(var.build_environment_variables) > 0 ? jsonencode(var.build_environment_variables) : null
    } : k => v if v != null
  }
}

################################################################################
# S3 Artifact Bucket
################################################################################

# An existing bucket is looked up (and must exist) unless the module is asked
# to create it.
data "aws_s3_bucket" "artifact" {
  count  = var.create_artifact_bucket ? 0 : 1
  bucket = var.artifact_bucket_name
}

resource "aws_s3_bucket" "artifact" {
  count  = var.create_artifact_bucket ? 1 : 0
  bucket = var.artifact_bucket_name

  force_destroy = var.artifact_bucket_force_destroy

  tags = merge(
    local.default_tags,
    {
      Name = "${local.name_prefix}-artifacts"
    }
  )
}

resource "aws_s3_bucket_versioning" "artifact" {
  count  = var.create_artifact_bucket ? 1 : 0
  bucket = aws_s3_bucket.artifact[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifact" {
  count  = var.create_artifact_bucket ? 1 : 0
  bucket = aws_s3_bucket.artifact[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.artifact_encryption_key_id != null ? "aws:kms" : "AES256"
      kms_master_key_id = var.artifact_encryption_key_id
    }
  }
}

resource "aws_s3_bucket_public_access_block" "artifact" {
  count  = var.create_artifact_bucket ? 1 : 0
  bucket = aws_s3_bucket.artifact[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

################################################################################
# IAM Role for Pipeline
################################################################################

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["codepipeline.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "pipeline" {
  count = var.create_role ? 1 : 0

  name                 = "${local.name_prefix}-pipeline-role"
  assume_role_policy   = data.aws_iam_policy_document.assume_role.json
  permissions_boundary = var.role_permissions_boundary

  tags = local.default_tags
}

data "aws_iam_policy_document" "pipeline" {
  # S3 artifact permissions
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:GetBucketVersioning",
      "s3:PutObject",
      "s3:PutObjectAcl"
    ]
    resources = [
      "arn:${local.partition}:s3:::${var.artifact_bucket_name}",
      "arn:${local.partition}:s3:::${var.artifact_bucket_name}/*"
    ]
  }

  # KMS encryption permissions
  dynamic "statement" {
    for_each = var.artifact_encryption_key_id != null ? [1] : []
    content {
      effect = "Allow"
      actions = [
        "kms:Decrypt",
        "kms:Encrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey"
      ]
      resources = [var.artifact_encryption_key_id]
    }
  }

  # CodeCommit permissions
  dynamic "statement" {
    for_each = var.source_provider == "CodeCommit" ? [1] : []
    content {
      effect = "Allow"
      actions = [
        "codecommit:GetBranch",
        "codecommit:GetCommit",
        "codecommit:UploadArchive",
        "codecommit:GetUploadArchiveStatus",
        "codecommit:CancelUploadArchive"
      ]
      resources = [
        "arn:${local.partition}:codecommit:${local.region}:${local.account_id}:${local.source_config.repository_name}"
      ]
    }
  }

  # CodeStar Connection permissions (GitHub)
  dynamic "statement" {
    for_each = var.source_provider == "GitHub" ? [1] : []
    content {
      effect = "Allow"
      actions = [
        "codestar-connections:UseConnection"
      ]
      resources = [local.source_config.connection_arn]
    }
  }

  # ECR permissions
  dynamic "statement" {
    for_each = var.source_provider == "ECR" ? [1] : []
    content {
      effect = "Allow"
      actions = [
        "ecr:DescribeImages",
        "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer"
      ]
      resources = [
        "arn:${local.partition}:ecr:${local.region}:${local.account_id}:repository/${local.source_config.repository_name_ecr}"
      ]
    }
  }

  # CodeBuild permissions
  dynamic "statement" {
    for_each = var.enable_build_stage || var.enable_test_stage ? [1] : []
    content {
      effect = "Allow"
      actions = [
        "codebuild:BatchGetBuilds",
        "codebuild:StartBuild"
      ]
      resources = compact([
        var.build_project_name != null ? "arn:${local.partition}:codebuild:${local.region}:${local.account_id}:project/${var.build_project_name}" : "",
        var.test_project_name != null ? "arn:${local.partition}:codebuild:${local.region}:${local.account_id}:project/${var.test_project_name}" : ""
      ])
    }
  }

  # CodeDeploy permissions
  dynamic "statement" {
    for_each = var.deploy_provider == "CodeDeploy" ? [1] : []
    content {
      effect = "Allow"
      actions = [
        "codedeploy:CreateDeployment",
        "codedeploy:GetApplication",
        "codedeploy:GetApplicationRevision",
        "codedeploy:GetDeployment",
        "codedeploy:GetDeploymentConfig",
        "codedeploy:RegisterApplicationRevision"
      ]
      resources = [
        "arn:${local.partition}:codedeploy:${local.region}:${local.account_id}:application:${var.deploy_configuration.application_name}",
        "arn:${local.partition}:codedeploy:${local.region}:${local.account_id}:deploymentgroup:${var.deploy_configuration.application_name}/${var.deploy_configuration.deployment_group}"
      ]
    }
  }

  # ECS permissions
  dynamic "statement" {
    for_each = var.deploy_provider == "ECS" ? [1] : []
    content {
      effect = "Allow"
      actions = [
        "ecs:DescribeServices",
        "ecs:DescribeTaskDefinition",
        "ecs:DescribeTasks",
        "ecs:ListTasks",
        "ecs:RegisterTaskDefinition",
        "ecs:UpdateService"
      ]
      resources = ["*"]
    }
  }

  dynamic "statement" {
    for_each = var.deploy_provider == "ECS" ? [1] : []
    content {
      effect = "Allow"
      actions = [
        "iam:PassRole"
      ]
      resources = ["*"]
      condition {
        test     = "StringEqualsIfExists"
        variable = "iam:PassedToService"
        values   = ["ecs-tasks.amazonaws.com"]
      }
    }
  }

  # Lambda permissions
  dynamic "statement" {
    for_each = var.deploy_provider == "Lambda" ? [1] : []
    content {
      effect = "Allow"
      actions = [
        "lambda:InvokeFunction",
        "lambda:GetFunction",
        "lambda:UpdateFunctionCode"
      ]
      resources = [
        "arn:${local.partition}:lambda:${local.region}:${local.account_id}:function:${var.deploy_configuration.function_name}"
      ]
    }
  }

  # CloudFormation permissions
  dynamic "statement" {
    for_each = var.deploy_provider == "CloudFormation" ? [1] : []
    content {
      effect = "Allow"
      actions = [
        "cloudformation:CreateStack",
        "cloudformation:DescribeStacks",
        "cloudformation:DeleteStack",
        "cloudformation:UpdateStack",
        "cloudformation:CreateChangeSet",
        "cloudformation:ExecuteChangeSet",
        "cloudformation:DeleteChangeSet",
        "cloudformation:DescribeChangeSet",
        "cloudformation:SetStackPolicy"
      ]
      resources = [
        "arn:${local.partition}:cloudformation:${local.region}:${local.account_id}:stack/${var.deploy_configuration.stack_name}/*"
      ]
    }
  }

  dynamic "statement" {
    for_each = var.deploy_provider == "CloudFormation" && var.deploy_configuration.role_arn != null ? [1] : []
    content {
      effect = "Allow"
      actions = [
        "iam:PassRole"
      ]
      resources = [var.deploy_configuration.role_arn]
    }
  }

  # SNS permissions for manual approval
  dynamic "statement" {
    for_each = var.enable_manual_approval && var.approval_sns_topic_arn != null ? [1] : []
    content {
      effect = "Allow"
      actions = [
        "sns:Publish"
      ]
      resources = [var.approval_sns_topic_arn]
    }
  }

  # Cross-account deployment permissions
  dynamic "statement" {
    for_each = var.enable_cross_account_deployment ? [1] : []
    content {
      effect = "Allow"
      actions = [
        "sts:AssumeRole"
      ]
      resources = var.cross_account_role_arns
    }
  }
}

resource "aws_iam_role_policy" "pipeline" {
  count = var.create_role ? 1 : 0

  name   = "${local.name_prefix}-pipeline-policy"
  role   = aws_iam_role.pipeline[0].id
  policy = data.aws_iam_policy_document.pipeline.json
}

################################################################################
# CodePipeline
################################################################################

resource "aws_codepipeline" "this" {
  name          = local.name_prefix
  role_arn      = var.create_role ? aws_iam_role.pipeline[0].arn : var.role_arn
  pipeline_type = var.pipeline_type

  # QUEUED and PARALLEL are only supported by V2 pipelines.
  execution_mode = var.pipeline_type == "V2" ? var.execution_mode : "SUPERSEDED"

  tags = local.default_tags

  artifact_store {
    location = var.create_artifact_bucket ? aws_s3_bucket.artifact[0].bucket : data.aws_s3_bucket.artifact[0].bucket
    type     = "S3"

    dynamic "encryption_key" {
      for_each = var.artifact_encryption_key_id != null ? [1] : []
      content {
        id   = var.artifact_encryption_key_id
        type = "KMS"
      }
    }
  }

  # Source Stage
  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = local.source_action_provider
      version          = "1"
      output_artifacts = [var.source_output_artifact]

      configuration = local.source_action_configuration
    }
  }

  # Build Stage
  dynamic "stage" {
    for_each = var.enable_build_stage ? [1] : []
    content {
      name = "Build"

      action {
        name             = "Build"
        category         = "Build"
        owner            = "AWS"
        provider         = "CodeBuild"
        version          = "1"
        input_artifacts  = [var.build_input_artifact]
        output_artifacts = [var.build_output_artifact]

        configuration = local.build_action_configuration
      }
    }
  }

  # Test Stage
  dynamic "stage" {
    for_each = var.enable_test_stage ? [1] : []
    content {
      name = "Test"

      action {
        name            = "Test"
        category        = "Test"
        owner           = "AWS"
        provider        = "CodeBuild"
        version         = "1"
        input_artifacts = [var.test_input_artifact]

        configuration = {
          ProjectName = var.test_project_name
        }
      }
    }
  }

  # Manual Approval Stage
  dynamic "stage" {
    for_each = var.enable_manual_approval ? [1] : []
    content {
      name = "Approval"

      action {
        name     = "ManualApproval"
        category = "Approval"
        owner    = "AWS"
        provider = "Manual"
        version  = "1"

        configuration = var.approval_sns_topic_arn != null ? {
          NotificationArn = var.approval_sns_topic_arn
          CustomData      = var.approval_notification_message
          } : {
          CustomData = var.approval_notification_message
        }
      }
    }
  }

  # Deploy Stage
  stage {
    name = "Deploy"

    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = var.deploy_provider
      version         = "1"
      input_artifacts = [var.deploy_input_artifact]

      configuration = local.deploy_action_configuration

      # Cross-account deployments assume the first target-account role.
      role_arn = var.enable_cross_account_deployment && length(var.cross_account_role_arns) > 0 ? var.cross_account_role_arns[0] : null
    }
  }

  lifecycle {
    ignore_changes = [
      stage[0].action[0].configuration["PollForSourceChanges"]
    ]
  }
}

################################################################################
# CloudWatch Event Rule for Pipeline Notifications
################################################################################

resource "aws_cloudwatch_event_rule" "pipeline" {
  count = var.enable_notifications && var.notification_target_arn != null ? 1 : 0

  name        = "${local.name_prefix}-pipeline-events"
  description = "Pipeline state change notifications for ${local.name_prefix}"

  event_pattern = jsonencode({
    source      = ["aws.codepipeline"]
    detail-type = var.notification_events
    detail = {
      pipeline = [aws_codepipeline.this.name]
    }
  })

  tags = local.default_tags
}

resource "aws_cloudwatch_event_target" "pipeline" {
  count = var.enable_notifications && var.notification_target_arn != null ? 1 : 0

  rule      = aws_cloudwatch_event_rule.pipeline[0].name
  target_id = "SendToSNSOrLambda"
  arn       = var.notification_target_arn
}

################################################################################
# CloudWatch Event Rule for Source Changes (CodeCommit)
################################################################################

resource "aws_cloudwatch_event_rule" "source" {
  count = var.source_provider == "CodeCommit" && local.source_config.detect_changes ? 1 : 0

  name        = "${local.name_prefix}-source-changes"
  description = "Trigger pipeline on CodeCommit changes"

  event_pattern = jsonencode({
    source      = ["aws.codecommit"]
    detail-type = ["CodeCommit Repository State Change"]
    detail = {
      event          = ["referenceCreated", "referenceUpdated"]
      repositoryName = [local.source_config.repository_name]
      referenceName  = [local.source_config.branch_name]
    }
  })

  tags = local.default_tags
}

resource "aws_cloudwatch_event_target" "source" {
  count = var.source_provider == "CodeCommit" && local.source_config.detect_changes ? 1 : 0

  rule      = aws_cloudwatch_event_rule.source[0].name
  target_id = "TriggerPipeline"
  arn       = aws_codepipeline.this.arn
  role_arn  = aws_iam_role.events[0].arn
}

data "aws_iam_policy_document" "events_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "events" {
  count = var.source_provider == "CodeCommit" && local.source_config.detect_changes ? 1 : 0

  name = "${local.name_prefix}-events-role"

  assume_role_policy = data.aws_iam_policy_document.events_assume_role.json

  tags = local.default_tags
}

resource "aws_iam_role_policy" "events" {
  count = var.source_provider == "CodeCommit" && local.source_config.detect_changes ? 1 : 0

  name = "${local.name_prefix}-events-policy"
  role = aws_iam_role.events[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "codepipeline:StartPipelineExecution"
      ]
      Resource = [
        aws_codepipeline.this.arn
      ]
    }]
  })
}
