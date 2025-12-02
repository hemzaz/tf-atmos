# CodeBuild Project Module

Production-ready AWS CodeBuild project with Docker support, VPC configuration, multiple cache strategies, and comprehensive logging.

## Features

- Multiple source providers (CodeCommit, GitHub, S3, CodePipeline)
- Docker build support with privileged mode
- VPC configuration for private resource access
- Environment variables from plaintext, SSM, Secrets Manager
- Build caching (S3, local Docker layers, source)
- CloudWatch Logs and S3 logs
- Multiple buildspec files support
- GitHub webhooks for automatic builds
- Batch builds for parallel execution
- Secondary sources and artifacts

## Example

```hcl
module "build_project" {
  source = "../../_library/cicd/codebuild-project/v1.0.0"

  name        = "my-app-build"
  description = "Build project for my application"

  # Source from GitHub
  source_type     = "GITHUB"
  source_location = "https://github.com/myorg/myapp"
  source_auth_type = "CODECONNECTIONS"
  source_auth_resource = "arn:aws:codestar-connections:us-east-1:123456789012:connection/xxx"

  # Docker build environment
  environment_compute_type    = "BUILD_GENERAL1_MEDIUM"
  environment_image           = "aws/codebuild/standard:7.0"
  environment_type            = "LINUX_CONTAINER"
  environment_privileged_mode = true

  # Environment variables
  environment_variables = [
    {
      name  = "AWS_DEFAULT_REGION"
      value = "us-east-1"
      type  = "PLAINTEXT"
    },
    {
      name  = "DOCKER_REGISTRY"
      value = "/prod/docker/registry"
      type  = "PARAMETER_STORE"
    },
    {
      name  = "DOCKER_PASSWORD"
      value = "prod/docker/password"
      type  = "SECRETS_MANAGER"
    }
  ]

  # VPC configuration for private resources
  enable_vpc_config  = true
  vpc_id             = "vpc-12345678"
  subnet_ids         = ["subnet-11111111", "subnet-22222222"]
  security_group_ids = ["sg-12345678"]

  # Local Docker layer caching
  cache_type  = "LOCAL"
  cache_modes = ["LOCAL_DOCKER_LAYER_CACHE", "LOCAL_SOURCE_CACHE"]

  # CloudWatch Logs
  enable_cloudwatch_logs = true

  # GitHub webhook for automatic builds
  enable_webhook = true
  webhook_filter_groups = [
    [
      {
        type    = "EVENT"
        pattern = "PUSH"
      },
      {
        type    = "HEAD_REF"
        pattern = "^refs/heads/main$"
      }
    ]
  ]

  build_timeout  = 30
  queued_timeout = 120

  tags = {
    Environment = "production"
    Application = "my-app"
  }
}
```
