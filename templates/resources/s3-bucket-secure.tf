# Secure S3 Bucket Resource Template
# Production-ready S3 bucket with security best practices: owner-enforced
# object ownership, public access block, default encryption, versioning and a
# bucket policy that denies non-TLS requests.
#
# Usage: copy this file into its own module directory (for example
# components/terraform/<component>/modules/s3-bucket/main.tf) and call it with
# a `module` block. It is self-contained: the module declares its own
# provider requirements and takes no provider configuration.

terraform {
  required_version = ">= 1.16.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
  }
}

locals {
  bucket_name   = "${var.name_prefix}-${var.bucket_purpose}"
  kms_encrypted = var.kms_key_id != null
}

# S3 Bucket
resource "aws_s3_bucket" "this" {
  bucket        = local.bucket_name
  force_destroy = var.force_destroy
  tags          = var.tags
}

# Disable ACLs: the bucket owner owns every object
resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Bucket versioning
resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = var.versioning_enabled ? "Enabled" : "Suspended"
  }
}

# Server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = local.kms_encrypted ? "aws:kms" : "AES256"
      kms_master_key_id = var.kms_key_id
    }

    bucket_key_enabled = local.kms_encrypted
  }
}

# Public access block (security best practice)
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = var.block_public_access
  block_public_policy     = var.block_public_access
  ignore_public_acls      = var.block_public_access
  restrict_public_buckets = var.block_public_access
}

# Lifecycle configuration
resource "aws_s3_bucket_lifecycle_configuration" "this" {
  count = length(var.lifecycle_rules) > 0 ? 1 : 0

  bucket = aws_s3_bucket.this.id

  dynamic "rule" {
    for_each = var.lifecycle_rules
    content {
      id     = rule.value.id
      status = rule.value.enabled ? "Enabled" : "Disabled"

      filter {
        prefix = rule.value.prefix
      }

      dynamic "expiration" {
        for_each = rule.value.expiration_days != null ? [rule.value.expiration_days] : []
        content {
          days = expiration.value
        }
      }

      dynamic "noncurrent_version_expiration" {
        for_each = rule.value.noncurrent_version_expiration_days != null ? [rule.value.noncurrent_version_expiration_days] : []
        content {
          noncurrent_days = noncurrent_version_expiration.value
        }
      }

      dynamic "transition" {
        for_each = rule.value.transitions
        content {
          days          = transition.value.days
          storage_class = transition.value.storage_class
        }
      }
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}

# Logging
resource "aws_s3_bucket_logging" "this" {
  count = var.logging_enabled ? 1 : 0

  bucket = aws_s3_bucket.this.id

  target_bucket = var.logging_target_bucket
  target_prefix = coalesce(var.logging_target_prefix, "access-logs/${local.bucket_name}/")
}

# Notification configuration
resource "aws_s3_bucket_notification" "this" {
  count = length(var.notification_configurations) > 0 ? 1 : 0

  bucket = aws_s3_bucket.this.id

  dynamic "lambda_function" {
    for_each = [for config in var.notification_configurations : config if config.type == "lambda"]
    content {
      lambda_function_arn = lambda_function.value.destination_arn
      events              = lambda_function.value.events
      filter_prefix       = lambda_function.value.filter_prefix
      filter_suffix       = lambda_function.value.filter_suffix
    }
  }

  dynamic "topic" {
    for_each = [for config in var.notification_configurations : config if config.type == "sns"]
    content {
      topic_arn     = topic.value.destination_arn
      events        = topic.value.events
      filter_prefix = topic.value.filter_prefix
      filter_suffix = topic.value.filter_suffix
    }
  }

  dynamic "queue" {
    for_each = [for config in var.notification_configurations : config if config.type == "sqs"]
    content {
      queue_arn     = queue.value.destination_arn
      events        = queue.value.events
      filter_prefix = queue.value.filter_prefix
      filter_suffix = queue.value.filter_suffix
    }
  }
}

# CORS configuration
resource "aws_s3_bucket_cors_configuration" "this" {
  count = length(var.cors_rules) > 0 ? 1 : 0

  bucket = aws_s3_bucket.this.id

  dynamic "cors_rule" {
    for_each = var.cors_rules
    content {
      allowed_headers = cors_rule.value.allowed_headers
      allowed_methods = cors_rule.value.allowed_methods
      allowed_origins = cors_rule.value.allowed_origins
      expose_headers  = cors_rule.value.expose_headers
      max_age_seconds = cors_rule.value.max_age_seconds
    }
  }
}

# Website configuration
resource "aws_s3_bucket_website_configuration" "this" {
  count = var.website_enabled ? 1 : 0

  bucket = aws_s3_bucket.this.id

  index_document {
    suffix = var.website_index_document
  }

  error_document {
    key = var.website_error_document
  }

  dynamic "routing_rule" {
    for_each = var.website_routing_rules
    content {
      condition {
        key_prefix_equals               = routing_rule.value.condition_key_prefix_equals
        http_error_code_returned_equals = routing_rule.value.condition_http_error_code
      }

      redirect {
        host_name               = routing_rule.value.redirect_host_name
        http_redirect_code      = routing_rule.value.redirect_http_code
        protocol                = routing_rule.value.redirect_protocol
        replace_key_prefix_with = routing_rule.value.redirect_replace_key_prefix
      }
    }
  }
}

# Bucket policy: always deny non-TLS access, merged with any caller policy
data "aws_iam_policy_document" "bucket" {
  source_policy_documents = var.bucket_policy != null ? [var.bucket_policy] : []

  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.this.arn,
      "${aws_s3_bucket.this.arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.bucket.json

  depends_on = [aws_s3_bucket_public_access_block.this]
}

# Variables
variable "name_prefix" {
  type        = string
  description = "Name prefix for the bucket (e.g. <tenant>-<account>-<environment>)"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]*$", var.name_prefix))
    error_message = "The name_prefix must contain only lowercase letters, numbers, dots and hyphens."
  }
}

variable "bucket_purpose" {
  type        = string
  description = "Purpose of the bucket (e.g., logs, data, assets)"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.bucket_purpose))
    error_message = "The bucket_purpose must contain only lowercase letters, numbers and hyphens."
  }
}

variable "force_destroy" {
  type        = bool
  description = "Delete all objects when the bucket is destroyed (never enable for production data)"
  default     = false
}

variable "versioning_enabled" {
  type        = bool
  description = "Enable S3 bucket versioning"
  default     = true
}

variable "kms_key_id" {
  type        = string
  description = "KMS key ARN or ID for SSE-KMS encryption (null for SSE-S3/AES256)"
  default     = null
}

variable "block_public_access" {
  type        = bool
  description = "Block all public access to the bucket"
  default     = true
}

variable "lifecycle_rules" {
  type = list(object({
    id                                 = string
    enabled                            = bool
    prefix                             = optional(string, "")
    expiration_days                    = optional(number)
    noncurrent_version_expiration_days = optional(number)
    transitions = optional(list(object({
      days          = number
      storage_class = string
    })), [])
  }))
  description = "Lifecycle rules for the bucket"
  default     = []

  validation {
    condition = alltrue(flatten([
      for rule in var.lifecycle_rules : [
        for t in rule.transitions : contains(["STANDARD_IA", "ONEZONE_IA", "INTELLIGENT_TIERING", "GLACIER", "GLACIER_IR", "DEEP_ARCHIVE"], t.storage_class)
      ]
    ]))
    error_message = "Transition storage_class must be one of STANDARD_IA, ONEZONE_IA, INTELLIGENT_TIERING, GLACIER, GLACIER_IR or DEEP_ARCHIVE."
  }
}

variable "logging_enabled" {
  type        = bool
  description = "Enable access logging"
  default     = false
}

variable "logging_target_bucket" {
  type        = string
  description = "Target bucket for access logs (required when logging_enabled is true)"
  default     = null
}

variable "logging_target_prefix" {
  type        = string
  description = "Prefix for access logs (defaults to access-logs/<bucket>/)"
  default     = null
}

variable "notification_configurations" {
  type = list(object({
    type            = string
    destination_arn = string
    events          = list(string)
    filter_prefix   = optional(string)
    filter_suffix   = optional(string)
  }))
  description = "S3 event notification configurations (type is lambda, sns or sqs)"
  default     = []

  validation {
    condition     = alltrue([for config in var.notification_configurations : contains(["lambda", "sns", "sqs"], config.type)])
    error_message = "Notification type must be one of lambda, sns or sqs."
  }
}

variable "cors_rules" {
  type = list(object({
    allowed_headers = list(string)
    allowed_methods = list(string)
    allowed_origins = list(string)
    expose_headers  = optional(list(string))
    max_age_seconds = optional(number)
  }))
  description = "CORS rules for the bucket"
  default     = []
}

variable "website_enabled" {
  type        = bool
  description = "Enable static website hosting"
  default     = false
}

variable "website_index_document" {
  type        = string
  description = "Index document for website"
  default     = "index.html"
}

variable "website_error_document" {
  type        = string
  description = "Error document for website"
  default     = "error.html"
}

variable "website_routing_rules" {
  type = list(object({
    condition_key_prefix_equals = optional(string)
    condition_http_error_code   = optional(string)
    redirect_host_name          = optional(string)
    redirect_http_code          = optional(string)
    redirect_protocol           = optional(string)
    redirect_replace_key_prefix = optional(string)
  }))
  description = "Website routing rules"
  default     = []
}

variable "bucket_policy" {
  type        = string
  description = "Additional bucket policy JSON, merged with the TLS-only statement (use an aws_iam_policy_document)"
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to the bucket"
  default     = {}
}

# Outputs
output "bucket_name" {
  description = "Name of the S3 bucket"
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.this.arn
}

output "bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.this.bucket_domain_name
}

output "bucket_regional_domain_name" {
  description = "Regional domain name of the S3 bucket"
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "bucket_hosted_zone_id" {
  description = "Hosted zone ID of the S3 bucket"
  value       = aws_s3_bucket.this.hosted_zone_id
}

output "bucket_website_endpoint" {
  description = "Website endpoint of the S3 bucket"
  value       = one(aws_s3_bucket_website_configuration.this[*].website_endpoint)
}

output "bucket_website_domain" {
  description = "Domain name of the website endpoint"
  value       = one(aws_s3_bucket_website_configuration.this[*].website_domain)
}
