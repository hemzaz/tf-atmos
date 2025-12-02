provider "aws" {
  region = "us-east-1"
}

module "s3_bucket" {
  source = "../../"

  name_prefix = "myapp"
  environment = "production"
  bucket_name = "myapp-production-data-20251202"  # Must be globally unique

  # Security
  enable_versioning   = true
  enable_mfa_delete   = false  # Set to true for critical buckets
  enable_encryption   = true
  encryption_type     = "sse-kms"
  kms_key_id          = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
  block_public_access = true

  # Lifecycle Management
  lifecycle_rules = [
    {
      id      = "archive-old-data"
      enabled = true
      prefix  = "data/"

      transitions = [
        {
          days          = 30
          storage_class = "STANDARD_IA"
        },
        {
          days          = 90
          storage_class = "INTELLIGENT_TIERING"
        },
        {
          days          = 180
          storage_class = "GLACIER"
        },
        {
          days          = 365
          storage_class = "DEEP_ARCHIVE"
        }
      ]

      noncurrent_version_transitions = [
        {
          noncurrent_days = 30
          storage_class   = "STANDARD_IA"
        },
        {
          noncurrent_days = 90
          storage_class   = "GLACIER"
        }
      ]

      noncurrent_version_expiration = {
        noncurrent_days = 365
      }
    },
    {
      id      = "expire-temp-files"
      enabled = true
      prefix  = "temp/"

      expiration = {
        days = 7
      }
    },
    {
      id                                     = "cleanup-incomplete-uploads"
      enabled                                = true
      abort_incomplete_multipart_upload_days = 7
    }
  ]

  # Logging
  enable_logging         = true
  logging_target_bucket  = "myapp-production-logs"
  logging_target_prefix  = "s3-access-logs/"

  # Replication (for disaster recovery)
  enable_replication  = true
  replication_role_arn = "arn:aws:iam::123456789012:role/s3-replication-role"
  replication_rules = [
    {
      id                        = "replicate-all"
      priority                  = 1
      destination_bucket_arn    = "arn:aws:s3:::myapp-dr-bucket"
      destination_storage_class = "STANDARD_IA"
      replica_kms_key_id        = "arn:aws:kms:us-west-2:123456789012:key/87654321-4321-4321-4321-210987654321"
    }
  ]

  # Intelligent-Tiering
  enable_intelligent_tiering            = true
  intelligent_tiering_archive_days      = 90
  intelligent_tiering_deep_archive_days = 180

  # Event Notifications
  event_notifications = [
    {
      id               = "notify-new-uploads"
      events           = ["s3:ObjectCreated:*"]
      destination_type = "sns"
      destination_arn  = "arn:aws:sns:us-east-1:123456789012:s3-uploads"
      filter_prefix    = "uploads/"
    },
    {
      id               = "process-images"
      events           = ["s3:ObjectCreated:*"]
      destination_type = "lambda"
      destination_arn  = "arn:aws:lambda:us-east-1:123456789012:function:image-processor"
      filter_suffix    = ".jpg"
    }
  ]

  # Monitoring
  enable_inventory       = true
  inventory_destination_bucket = "myapp-inventory-bucket"
  enable_request_metrics = true

  tags = {
    Terraform   = "true"
    Owner       = "platform-team"
    CostCenter  = "engineering"
    Compliance  = "hipaa"
    DataClass   = "sensitive"
    Backup      = "required"
  }
}
