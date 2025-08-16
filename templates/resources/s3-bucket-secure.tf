# Secure S3 Bucket Resource Template
# Production-ready S3 bucket with security best practices

locals {
  bucket_name = "${var.name_prefix}-${var.bucket_purpose}"
}

# S3 Bucket
resource "aws_s3_bucket" "this" {
  bucket = local.bucket_name
  tags   = var.tags
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
      sse_algorithm     = var.kms_key_id != "" ? "aws:kms" : "AES256"
      kms_master_key_id = var.kms_key_id != "" ? var.kms_key_id : null
    }
    
    bucket_key_enabled = var.kms_key_id != "" ? true : false
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
      
      dynamic "expiration" {
        for_each = rule.value.expiration_days != null ? [1] : []
        content {
          days = rule.value.expiration_days
        }
      }
      
      dynamic "noncurrent_version_expiration" {
        for_each = rule.value.noncurrent_version_expiration_days != null ? [1] : []
        content {
          noncurrent_days = rule.value.noncurrent_version_expiration_days
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
}

# Logging
resource "aws_s3_bucket_logging" "this" {
  count = var.logging_enabled ? 1 : 0
  
  bucket = aws_s3_bucket.this.id
  
  target_bucket = var.logging_target_bucket
  target_prefix = var.logging_target_prefix != "" ? var.logging_target_prefix : "access-logs/${local.bucket_name}/"
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
        key_prefix_equals = routing_rule.value.condition_key_prefix_equals
        http_error_code_returned_equals = routing_rule.value.condition_http_error_code
      }
      
      redirect {
        host_name     = routing_rule.value.redirect_host_name
        http_redirect_code = routing_rule.value.redirect_http_code
        protocol      = routing_rule.value.redirect_protocol
        replace_key_prefix_with = routing_rule.value.redirect_replace_key_prefix
      }
    }
  }
}

# Bucket policy
resource "aws_s3_bucket_policy" "this" {
  count = var.bucket_policy != "" ? 1 : 0
  
  bucket = aws_s3_bucket.this.id
  policy = var.bucket_policy
}

# Variables
variable "name_prefix" {
  type        = string
  description = "Name prefix for the bucket"
}

variable "bucket_purpose" {
  type        = string
  description = "Purpose of the bucket (e.g., logs, data, assets)"
}

variable "versioning_enabled" {
  type        = bool
  description = "Enable S3 bucket versioning"
  default     = true
}

variable "kms_key_id" {
  type        = string
  description = "KMS key ID for encryption (empty for AES256)"
  default     = ""
}

variable "block_public_access" {
  type        = bool
  description = "Block all public access to the bucket"
  default     = true
}

variable "lifecycle_rules" {
  type = list(object({
    id                                   = string
    enabled                             = bool
    expiration_days                     = optional(number)
    noncurrent_version_expiration_days  = optional(number)
    transitions = list(object({
      days          = number
      storage_class = string
    }))
  }))
  description = "Lifecycle rules for the bucket"
  default     = []
}

variable "logging_enabled" {
  type        = bool
  description = "Enable access logging"
  default     = false
}

variable "logging_target_bucket" {
  type        = string
  description = "Target bucket for access logs"
  default     = ""
}

variable "logging_target_prefix" {
  type        = string
  description = "Prefix for access logs"
  default     = ""
}

variable "notification_configurations" {
  type = list(object({
    type            = string # lambda, sns, or sqs
    destination_arn = string
    events          = list(string)
    filter_prefix   = optional(string)
    filter_suffix   = optional(string)
  }))
  description = "S3 event notification configurations"
  default     = []
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
    condition_key_prefix_equals    = optional(string)
    condition_http_error_code      = optional(string)
    redirect_host_name            = optional(string)
    redirect_http_code            = optional(string)
    redirect_protocol             = optional(string)
    redirect_replace_key_prefix   = optional(string)
  }))
  description = "Website routing rules"
  default     = []
}

variable "bucket_policy" {
  type        = string
  description = "Bucket policy JSON"
  default     = ""
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
  value       = var.website_enabled ? aws_s3_bucket_website_configuration.this[0].website_endpoint : null
}

output "bucket_website_domain" {
  description = "Domain name of the website endpoint"
  value       = var.website_enabled ? aws_s3_bucket_website_configuration.this[0].website_domain : null
}