# CodePipeline Module

Production-ready AWS CodePipeline with multiple source/deploy providers, cross-account support, and comprehensive monitoring.

## Features

- Multiple source providers (CodeCommit, GitHub, S3, ECR)
- Multiple deploy targets (CodeDeploy, ECS, Lambda, CloudFormation, S3)
- Optional build and test stages
- Manual approval stage with SNS notifications
- Cross-account deployment support
- Artifact encryption with KMS
- CloudWatch Events for pipeline notifications
- Pipeline V2 with advanced execution modes (`execution_mode`)
- Artifact bucket: an existing bucket is used by default; set `create_artifact_bucket = true` to have the module create it (versioned, encrypted, public access blocked)
- GitHub sources use a CodeConnections/CodeStar connection (`CodeStarSourceConnection` action)

## Requirements

- Terraform >= 1.16.0, < 2.0.0
- AWS provider >= 6.0, < 7.0

## Example

```hcl
module "pipeline" {
  source = "../../_library/cicd/codepipeline/v1.0.0"

  name                 = "my-app-pipeline"
  artifact_bucket_name   = "my-pipeline-artifacts"
  create_artifact_bucket = true

  # Source from GitHub
  source_provider = "GitHub"
  source_configuration = {
    connection_arn  = "arn:aws:codestar-connections:us-east-1:123456789012:connection/xxx"
    repository_name = "myorg/myapp"
    branch_name     = "main"
    detect_changes  = true
  }

  # Build with CodeBuild
  enable_build_stage  = true
  build_project_name  = "my-app-build"
  build_environment_variables = [
    {
      name  = "ENVIRONMENT"
      value = "production"
      type  = "PLAINTEXT"
    }
  ]

  # Manual approval before deploy
  enable_manual_approval        = true
  approval_sns_topic_arn        = "arn:aws:sns:us-east-1:123456789012:approvals"
  approval_notification_message = "Approve production deployment"

  # Deploy to ECS
  deploy_provider = "ECS"
  deploy_configuration = {
    cluster_name = "my-cluster"
    service_name = "my-service"
    file_name    = "imagedefinitions.json"
  }

  # Notifications
  enable_notifications    = true
  notification_target_arn = "arn:aws:sns:us-east-1:123456789012:pipeline-alerts"

  tags = {
    Environment = "production"
    Application = "my-app"
  }
}
```
