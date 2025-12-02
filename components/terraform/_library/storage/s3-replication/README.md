# S3 Replication Module

Production-ready S3 replication for cross-region or same-region disaster recovery with Replication Time Control (RTC) and metrics.

## Features

- Cross-region or same-region S3 replication
- Replication rules with prefix and tag filters
- Replication Time Control (RTC) for 15-minute SLA
- S3 Batch Replication support for existing objects
- Replication metrics and events
- KMS encryption support for replicated objects
- IAM role with least privilege access
- Delete marker replication
- Replica modification replication
- CloudWatch alarms for replication monitoring
- Cross-account replication support

## Usage

```hcl
module "s3_replication" {
  source = "../../_library/storage/s3-replication"

  name_prefix = "myapp"
  environment = "production"

  source_bucket_id      = "my-source-bucket"
  destination_bucket_id = "my-destination-bucket"
  destination_region    = "us-west-2"

  enable_kms_encryption     = true
  source_kms_key_arn        = "arn:aws:kms:us-east-1:123456789012:key/source-key-id"
  destination_kms_key_arn   = "arn:aws:kms:us-west-2:123456789012:key/dest-key-id"

  replication_rules = [
    {
      id                              = "replicate-critical"
      priority                        = 1
      filter_prefix                   = "critical/"
      destination_storage_class       = "STANDARD_IA"
      enable_replication_time_control = true
      replication_time_minutes        = 15
      enable_metrics                  = true
      delete_marker_replication_status = "Enabled"
    },
    {
      id                        = "replicate-logs"
      priority                  = 2
      filter_tags               = { Type = "logs" }
      destination_storage_class = "GLACIER_IR"
      enable_metrics            = true
    }
  ]

  tags = {
    Compliance = "DR"
  }

  providers = {
    aws.replica = aws.us-west-2
  }
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5.0 |
| aws | >= 5.0.0 |

## Provider Configuration

This module requires two AWS provider configurations:
- Default provider for the source region
- `aws.replica` provider for the destination region

## Inputs

See `variables.tf` for all available inputs.

## Outputs

See `outputs.tf` for all available outputs.
