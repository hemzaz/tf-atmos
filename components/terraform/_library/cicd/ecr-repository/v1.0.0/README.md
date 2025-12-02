# ECR Repository Module

Production-ready AWS ECR repository with lifecycle policies, image scanning, cross-account permissions, encryption, and replication.

## Features

- Image scanning on push (basic or enhanced)
- Image tag immutability
- Automatic lifecycle policies for cleanup
- Cross-account permissions
- KMS encryption
- Cross-region replication
- CloudWatch metrics and alarms
- Pull through cache support

## Example

```hcl
module "ecr_repository" {
  source = "../../_library/cicd/ecr-repository/v1.0.0"

  name = "my-app"

  # Image configuration
  image_tag_mutability = "IMMUTABLE"

  # Enhanced scanning
  enable_scan_on_push = true
  scan_type           = "ENHANCED"
  scan_frequency      = "CONTINUOUS_SCAN"

  # KMS encryption
  encryption_type = "KMS"
  kms_key_id      = "arn:aws:kms:us-east-1:123456789012:key/xxx"

  # Lifecycle policy
  enable_lifecycle_policy        = true
  untagged_image_retention_days  = 7
  tagged_image_count_limit       = 30

  # Cross-account access
  cross_account_principals = [
    "arn:aws:iam::987654321098:root",
    "123456789012"
  ]

  # Cross-region replication
  enable_replication = true
  replication_destinations = [
    {
      region      = "us-west-2"
      registry_id = "123456789012"
    },
    {
      region      = "eu-west-1"
      registry_id = "123456789012"
    }
  ]

  # CloudWatch monitoring
  enable_cloudwatch_metrics = true

  tags = {
    Environment = "production"
    Application = "my-app"
  }
}
```
