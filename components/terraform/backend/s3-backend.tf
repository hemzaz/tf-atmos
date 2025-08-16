/*
 * This file implements a proper dependency graph for S3 backend resources.
 * 
 * Resource creation order:
 * 1. Base buckets (terraform_state, terraform_state_logs)
 * 2. KMS key for encryption
 * 3. Basic bucket configurations (versioning, acls, encryption)
 * 4. Access logs bucket and its configuration
 * 5. Bucket policies and logging configurations that reference other resources
 *
 * Dependencies are explicitly declared using Terraform's depends_on attribute
 * to ensure resources are created in the correct order and avoid circular dependencies.
 */

locals {
  # Define local variables for dependency management
  # Consolidated dependencies into a single, more efficient structure
  dependencies = {
    # Base bucket resources have no dependencies
    base = []

    # Policy resources depend on the buckets being created
    policy = [
      aws_s3_bucket.terraform_state,
      aws_s3_bucket.terraform_state_logs
    ]

    # Logging resources depend on the access logs bucket being configured
    logging = [
      aws_s3_bucket.terraform_state_access_logs,
      aws_s3_bucket_acl.terraform_state_access_logs
    ]
  }
}

resource "aws_s3_bucket" "terraform_state" {
  bucket = var.bucket_name

  lifecycle {
    prevent_destroy = true
  }

  tags = var.tags
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
    # Disabled MFA delete as it requires additional configuration and authentication
    # which isn't supported in the default Terraform workflow
    mfa_delete = "Disabled"
  }
}

# Create KMS key for bucket encryption
resource "aws_kms_key" "terraform_state_key" {
  description             = "KMS key for Terraform state encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.account_id}:root"
        }
        Action = [
          "kms:Create*",
          "kms:Describe*",
          "kms:Enable*",
          "kms:List*",
          "kms:Put*",
          "kms:Update*",
          "kms:Revoke*",
          "kms:Disable*",
          "kms:Get*",
          "kms:Delete*",
          "kms:TagResource",
          "kms:UntagResource",
          "kms:ScheduleKeyDeletion",
          "kms:CancelKeyDeletion"
        ]
        Resource = aws_kms_key.terraform_state_key.arn
      }
    ]
  })

  tags = var.tags
}

resource "aws_kms_alias" "terraform_state_key_alias" {
  name          = "alias/${var.tenant}-terraform-state-key"
  target_key_id = aws_kms_key.terraform_state_key.key_id
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.terraform_state_key.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_acl" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  acl    = "private"
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Add policy to enforce HTTPS only
resource "aws_s3_bucket_policy" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnforceHTTPS"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.terraform_state.arn,
          "${aws_s3_bucket.terraform_state.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })

  # Using local variable for policy dependencies
  # Ensures bucket exists before policy is applied and prevents race conditions
  depends_on = concat([
    aws_s3_bucket_versioning.terraform_state
  ], local.dependencies.policy)
}
resource "aws_s3_bucket" "terraform_state_logs" {
  bucket = "${var.bucket_name}-logs"

  lifecycle {
    prevent_destroy = true
  }

  tags = var.tags
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state_logs" {
  bucket = aws_s3_bucket.terraform_state_logs.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.terraform_state_key.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_acl" "terraform_state_logs" {
  bucket = aws_s3_bucket.terraform_state_logs.id
  acl    = "log-delivery-write"
}

resource "aws_s3_bucket_public_access_block" "terraform_state_logs" {
  bucket = aws_s3_bucket.terraform_state_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "terraform_state_logs" {
  bucket = aws_s3_bucket.terraform_state_logs.id

  rule {
    id     = "logs-retention"
    status = "Enabled"

    expiration {
      days = 90
    }
  }
}

# Add policy to enforce HTTPS for logs bucket too
resource "aws_s3_bucket_policy" "terraform_state_logs" {
  bucket = aws_s3_bucket.terraform_state_logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnforceHTTPS"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.terraform_state_logs.arn,
          "${aws_s3_bucket.terraform_state_logs.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })

  # Using consolidated dependencies for consistency
  depends_on = concat([
    aws_s3_bucket_lifecycle_configuration.terraform_state_logs
  ], local.dependencies.policy)
}

/* Proper Circular Dependency Resolution
 *
 * This access logs bucket solves a circular dependency problem:
 * - The main state bucket needs to log to an access logs bucket
 * - The access logs bucket itself needs to be secured and configured
 *
 * Instead of arbitrarily breaking the cycle by creating separate unrelated buckets,
 * we use Terraform's depends_on to create a proper dependency graph:
 * 
 * 1. First, create the main buckets
 * 2. Then create the access logs bucket with a dependency on the main buckets
 * 3. Configure the access logs bucket
 * 4. Finally, set up the logging on the main buckets with depends_on to the access logs config
 *
 * This approach ensures everything is created in the right order without arbitrary splitting.
 */
resource "aws_s3_bucket" "terraform_state_access_logs" {
  bucket = "${var.bucket_name}-access-logs"

  lifecycle {
    prevent_destroy = true
  }

  # Creates a dependency graph that ensures main state bucket is created first
  # before access logs can reference it
  depends_on = local.dependencies.policy

  tags = var.tags
}

resource "aws_s3_bucket_acl" "terraform_state_access_logs" {
  bucket = aws_s3_bucket.terraform_state_access_logs.id
  acl    = "log-delivery-write"

  # Explicit dependency to ensure bucket exists before ACL is applied
  depends_on = [aws_s3_bucket.terraform_state_access_logs]
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state_access_logs" {
  bucket = aws_s3_bucket.terraform_state_access_logs.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.terraform_state_key.arn
      sse_algorithm     = "aws:kms"
    }
  }

  # Explicit dependencies to ensure KMS key and bucket exist before encryption is applied
  depends_on = [
    aws_s3_bucket.terraform_state_access_logs,
    aws_kms_key.terraform_state_key
  ]
}

resource "aws_s3_bucket_public_access_block" "terraform_state_access_logs" {
  bucket = aws_s3_bucket.terraform_state_access_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  # Explicit dependency to ensure bucket exists before access block is applied
  depends_on = [aws_s3_bucket.terraform_state_access_logs]
}

resource "aws_s3_bucket_lifecycle_configuration" "terraform_state_access_logs" {
  bucket = aws_s3_bucket.terraform_state_access_logs.id

  rule {
    id     = "access-logs-retention"
    status = "Enabled"

    expiration {
      days = 90
    }
  }

  # Explicit dependency to ensure bucket exists before lifecycle configuration is applied
  depends_on = [aws_s3_bucket.terraform_state_access_logs]
}

# Set up logging for main state bucket with explicit dependency declaration
resource "aws_s3_bucket_logging" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  target_bucket = aws_s3_bucket.terraform_state_access_logs.id
  target_prefix = "state-bucket-logs/"

  # Using the improved structure for dependencies
  # makes the code more maintainable and efficient  
  depends_on = concat(local.dependencies.logging, [
    aws_s3_bucket_server_side_encryption_configuration.terraform_state_access_logs
  ])
}

resource "aws_s3_bucket_logging" "terraform_state_logs" {
  bucket = aws_s3_bucket.terraform_state_logs.id

  target_bucket = aws_s3_bucket.terraform_state_access_logs.id
  target_prefix = "logs-bucket-logs/"

  # Using the improved structure for dependencies
  # makes the code more maintainable and efficient
  depends_on = concat(local.dependencies.logging, [
    aws_s3_bucket_server_side_encryption_configuration.terraform_state_access_logs
  ])
}

resource "aws_s3_bucket_lifecycle_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    id     = "state-retention"
    status = "Enabled"

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_transition {
      noncurrent_days = 90
      storage_class   = "GLACIER"
    }

    noncurrent_version_expiration {
      noncurrent_days = 365
    }
  }
}