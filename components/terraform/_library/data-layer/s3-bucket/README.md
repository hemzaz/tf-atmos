# S3 Bucket - Production-Ready S3 Module

## Overview

This module creates a production-ready S3 bucket with comprehensive security, versioning, lifecycle policies, replication, and logging features.

## Features

- Server-side encryption (SSE-S3, SSE-KMS, or DSSE-KMS)
- Versioning with optional MFA delete
- Lifecycle rules for transition and expiration
- Cross-region replication (optional)
- Bucket logging to another S3 bucket
- Public access block (enabled by default)
- Bucket policies with least privilege
- Object lock for compliance (optional)
- Intelligent-Tiering, Glacier transitions
- Event notifications (SNS, SQS, Lambda)
- CORS configuration (optional)
- Website hosting (optional)
- Request metrics and inventory

## Usage

### Secure Private Bucket

```hcl
module "s3_bucket" {
  source = "../../_library/data-layer/s3-bucket"

  name_prefix = "myapp"
  environment = "production"
  bucket_name = "myapp-data"

  enable_versioning = true
  enable_encryption = true
  encryption_type   = "sse-kms"
  kms_key_id        = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"

  block_public_access = true

  lifecycle_rules = [
    {
      id      = "archive-old-versions"
      enabled = true
      noncurrent_version_transitions = [
        {
          days          = 30
          storage_class = "STANDARD_IA"
        },
        {
          days          = 90
          storage_class = "GLACIER"
        }
      ]
      noncurrent_version_expiration = {
        days = 365
      }
    },
    {
      id      = "expire-incomplete-uploads"
      enabled = true
      abort_incomplete_multipart_upload_days = 7
    }
  ]

  tags = {
    Compliance = "hipaa"
    DataClass  = "sensitive"
  }
}
```

### Public Website Bucket

```hcl
module "website_bucket" {
  source = "../../_library/data-layer/s3-bucket"

  name_prefix = "myapp"
  environment = "production"
  bucket_name = "myapp-website"

  enable_website = true
  website_index_document = "index.html"
  website_error_document = "error.html"

  block_public_access = false
  enable_public_read  = true

  cors_rules = [
    {
      allowed_headers = ["*"]
      allowed_methods = ["GET", "HEAD"]
      allowed_origins = ["https://example.com"]
      expose_headers  = ["ETag"]
      max_age_seconds = 3000
    }
  ]

  tags = {
    Purpose = "website-hosting"
  }
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5.0 |
| aws | >= 5.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name_prefix | Name prefix for resources | `string` | n/a | yes |
| environment | Environment name | `string` | n/a | yes |
| bucket_name | Name of the S3 bucket | `string` | n/a | yes |
| enable_versioning | Enable versioning | `bool` | `true` | no |
| enable_encryption | Enable server-side encryption | `bool` | `true` | no |
| encryption_type | Encryption type (sse-s3, sse-kms, dsse-kms) | `string` | `"sse-s3"` | no |
| kms_key_id | KMS key ID for SSE-KMS encryption | `string` | `null` | no |
| block_public_access | Block all public access | `bool` | `true` | no |
| lifecycle_rules | Lifecycle rules | `list(any)` | `[]` | no |
| enable_website | Enable static website hosting | `bool` | `false` | no |
| cors_rules | CORS rules | `list(any)` | `[]` | no |
| tags | Additional tags | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| bucket_id | ID of the bucket |
| bucket_arn | ARN of the bucket |
| bucket_domain_name | Domain name of the bucket |
| bucket_regional_domain_name | Regional domain name |
| website_endpoint | Website endpoint (if enabled) |

## Best Practices

1. Always enable versioning for production buckets
2. Use KMS encryption for sensitive data
3. Enable access logging for audit trails
4. Set up lifecycle policies to reduce costs
5. Block public access unless explicitly needed
6. Use bucket policies for least-privilege access
7. Enable MFA delete for critical buckets
8. Configure cross-region replication for DR

## Changelog

See [CHANGELOG.md](./CHANGELOG.md) for version history.
