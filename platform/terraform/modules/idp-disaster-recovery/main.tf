# IDP Disaster Recovery Module
# Implements cross-region replication, backup strategies, and failover mechanisms

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"

      configuration_aliases = [
        aws.primary,
        aws.secondary
      ]
    }
  }
}

locals {
  name_prefix = "${var.tenant}-${var.environment}-idp"

  common_tags = merge(
    var.tags,
    {
      Tenant      = var.tenant
      Environment = var.environment
      Component   = "idp-disaster-recovery"
      ManagedBy   = "Terraform"
    }
  )
}

# S3 Bucket for Backup Storage (Primary Region)
resource "aws_s3_bucket" "backup_primary" {
  provider = aws.primary

  bucket = "${local.name_prefix}-backup-${var.primary_region}-${data.aws_caller_identity.current.account_id}"

  tags = merge(
    local.common_tags,
    {
      Name   = "${local.name_prefix}-backup-primary"
      Region = var.primary_region
    }
  )
}

resource "aws_s3_bucket_versioning" "backup_primary" {
  provider = aws.primary
  bucket   = aws_s3_bucket.backup_primary.id

  versioning_configuration {
    status     = "Enabled"
    mfa_delete = var.environment == "prod" ? "Enabled" : "Disabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backup_primary" {
  provider = aws.primary
  bucket   = aws_s3_bucket.backup_primary.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_id
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "backup_primary" {
  provider = aws.primary
  bucket   = aws_s3_bucket.backup_primary.id

  rule {
    id     = "transition-old-backups"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    transition {
      days          = 365
      storage_class = "DEEP_ARCHIVE"
    }

    expiration {
      days = var.backup_retention_days
    }
  }
}

# S3 Bucket for Backup Storage (Secondary Region)
resource "aws_s3_bucket" "backup_secondary" {
  provider = aws.secondary

  bucket = "${local.name_prefix}-backup-${var.secondary_region}-${data.aws_caller_identity.current.account_id}"

  tags = merge(
    local.common_tags,
    {
      Name   = "${local.name_prefix}-backup-secondary"
      Region = var.secondary_region
    }
  )
}

resource "aws_s3_bucket_versioning" "backup_secondary" {
  provider = aws.secondary
  bucket   = aws_s3_bucket.backup_secondary.id

  versioning_configuration {
    status     = "Enabled"
    mfa_delete = var.environment == "prod" ? "Enabled" : "Disabled"
  }
}

# Cross-Region Replication Configuration
resource "aws_iam_role" "replication" {
  provider = aws.primary
  name     = "${local.name_prefix}-s3-replication"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "replication" {
  provider = aws.primary
  name     = "${local.name_prefix}-s3-replication"
  role     = aws_iam_role.replication.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.backup_primary.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionTagging"
        ]
        Resource = "${aws_s3_bucket.backup_primary.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags"
        ]
        Resource = "${aws_s3_bucket.backup_secondary.arn}/*"
      }
    ]
  })
}

resource "aws_s3_bucket_replication_configuration" "backup" {
  provider = aws.primary

  role   = aws_iam_role.replication.arn
  bucket = aws_s3_bucket.backup_primary.id

  rule {
    id       = "replicate-all-objects"
    status   = "Enabled"
    priority = 1

    filter {}

    delete_marker_replication {
      status = "Enabled"
    }

    destination {
      bucket        = aws_s3_bucket.backup_secondary.arn
      storage_class = "STANDARD_IA"

      replication_time {
        status = "Enabled"
        time {
          minutes = 15
        }
      }

      metrics {
        status = "Enabled"
        event_threshold {
          minutes = 15
        }
      }
    }
  }

  depends_on = [aws_s3_bucket_versioning.backup_primary]
}

# Data source for current account
data "aws_caller_identity" "current" {}

# AWS Backup Plan
resource "aws_backup_plan" "main" {
  provider = aws.primary
  name     = "${local.name_prefix}-backup-plan"

  rule {
    rule_name         = "daily-backups"
    target_vault_name = aws_backup_vault.primary.name
    schedule          = "cron(0 2 * * ? *)" # Daily at 2 AM UTC
    start_window      = 60
    completion_window = 180

    lifecycle {
      cold_storage_after = 30
      delete_after       = var.backup_retention_days
    }

    recovery_point_tags = local.common_tags
  }

  rule {
    rule_name         = "hourly-critical"
    target_vault_name = aws_backup_vault.primary.name
    schedule          = "cron(0 * * * ? *)" # Every hour
    start_window      = 60
    completion_window = 120

    lifecycle {
      delete_after = 7
    }

    recovery_point_tags = merge(
      local.common_tags,
      {
        Type = "Hourly"
      }
    )
  }

  advanced_backup_setting {
    backup_options = {
      WindowsVSS = "enabled"
    }
    resource_type = "EC2"
  }

  tags = local.common_tags
}

# Backup Vault (Primary)
resource "aws_backup_vault" "primary" {
  provider    = aws.primary
  name        = "${local.name_prefix}-vault-primary"
  kms_key_arn = var.kms_key_arn

  tags = merge(
    local.common_tags,
    {
      Region = var.primary_region
    }
  )
}

# Backup Vault (Secondary)
resource "aws_backup_vault" "secondary" {
  provider    = aws.secondary
  name        = "${local.name_prefix}-vault-secondary"
  kms_key_arn = var.secondary_kms_key_arn

  tags = merge(
    local.common_tags,
    {
      Region = var.secondary_region
    }
  )
}

# Backup Selection
resource "aws_backup_selection" "main" {
  provider     = aws.primary
  name         = "${local.name_prefix}-backup-selection"
  plan_id      = aws_backup_plan.main.id
  iam_role_arn = aws_iam_role.backup.arn

  resources = var.backup_resources

  selection_tag {
    type  = "STRINGEQUALS"
    key   = "Backup"
    value = "true"
  }

  condition {
    string_equals {
      key   = "aws:ResourceTag/Environment"
      value = var.environment
    }
  }
}

# IAM Role for AWS Backup
resource "aws_iam_role" "backup" {
  provider = aws.primary
  name     = "${local.name_prefix}-backup-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "backup.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "backup" {
  provider   = aws.primary
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_iam_role_policy_attachment" "backup_restore" {
  provider   = aws.primary
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

# DynamoDB Global Table for State Management
resource "aws_dynamodb_table" "dr_state" {
  provider         = aws.primary
  name             = "${local.name_prefix}-dr-state"
  billing_mode     = "PAY_PER_REQUEST"
  hash_key         = "id"
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  attribute {
    name = "id"
    type = "S"
  }

  replica {
    region_name = var.secondary_region
    kms_key_arn = var.secondary_kms_key_arn
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_key_arn
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = local.common_tags
}

# Route53 Health Checks
resource "aws_route53_health_check" "primary" {
  provider          = aws.primary
  fqdn              = var.primary_endpoint
  port              = 443
  type              = "HTTPS"
  resource_path     = "/health"
  failure_threshold = 3
  request_interval  = 30

  tags = merge(
    local.common_tags,
    {
      Name   = "${local.name_prefix}-primary-health"
      Region = var.primary_region
    }
  )
}

resource "aws_route53_health_check" "secondary" {
  provider          = aws.primary
  fqdn              = var.secondary_endpoint
  port              = 443
  type              = "HTTPS"
  resource_path     = "/health"
  failure_threshold = 3
  request_interval  = 30

  tags = merge(
    local.common_tags,
    {
      Name   = "${local.name_prefix}-secondary-health"
      Region = var.secondary_region
    }
  )
}

# Route53 Failover Records
resource "aws_route53_record" "primary" {
  provider = aws.primary
  zone_id  = var.route53_zone_id
  name     = var.domain_name
  type     = "A"

  alias {
    name                   = var.primary_alb_dns_name
    zone_id                = var.primary_alb_zone_id
    evaluate_target_health = true
  }

  set_identifier = "Primary"

  failover_routing_policy {
    type = "PRIMARY"
  }

  health_check_id = aws_route53_health_check.primary.id
}

resource "aws_route53_record" "secondary" {
  provider = aws.primary
  zone_id  = var.route53_zone_id
  name     = var.domain_name
  type     = "A"

  alias {
    name                   = var.secondary_alb_dns_name
    zone_id                = var.secondary_alb_zone_id
    evaluate_target_health = true
  }

  set_identifier = "Secondary"

  failover_routing_policy {
    type = "SECONDARY"
  }

  health_check_id = aws_route53_health_check.secondary.id
}

# CloudWatch Alarms for DR Monitoring
resource "aws_cloudwatch_metric_alarm" "backup_failure" {
  provider            = aws.primary
  alarm_name          = "${local.name_prefix}-backup-failure"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "NumberOfBackupJobsCompleted"
  namespace           = "AWS/Backup"
  period              = 86400 # 24 hours
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Alert when backup jobs fail"
  alarm_actions       = [var.sns_topic_arn]

  dimensions = {
    BackupVaultName = aws_backup_vault.primary.name
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "replication_latency" {
  provider            = aws.primary
  alarm_name          = "${local.name_prefix}-replication-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ReplicationLatency"
  namespace           = "AWS/S3"
  period              = 300
  statistic           = "Maximum"
  threshold           = 900 # 15 minutes in seconds
  alarm_description   = "Alert when S3 replication latency is high"
  alarm_actions       = [var.sns_topic_arn]

  dimensions = {
    SourceBucket      = aws_s3_bucket.backup_primary.id
    DestinationBucket = aws_s3_bucket.backup_secondary.id
  }

  tags = local.common_tags
}

# Lambda Function for Automated Failover
resource "aws_lambda_function" "failover_orchestrator" {
  provider         = aws.primary
  filename         = "${path.module}/lambda/failover.zip"
  function_name    = "${local.name_prefix}-failover-orchestrator"
  role             = aws_iam_role.failover_lambda.arn
  handler          = "index.handler"
  source_code_hash = filebase64sha256("${path.module}/lambda/failover.zip")
  runtime          = "python3.11"
  timeout          = 300
  memory_size      = 512

  environment {
    variables = {
      PRIMARY_REGION   = var.primary_region
      SECONDARY_REGION = var.secondary_region
      STATE_TABLE      = aws_dynamodb_table.dr_state.name
      SNS_TOPIC_ARN    = var.sns_topic_arn
    }
  }

  vpc_config {
    subnet_ids         = var.lambda_subnet_ids
    security_group_ids = [var.lambda_security_group_id]
  }

  tags = local.common_tags
}

# IAM Role for Failover Lambda
resource "aws_iam_role" "failover_lambda" {
  provider = aws.primary
  name     = "${local.name_prefix}-failover-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "failover_lambda" {
  provider = aws.primary
  name     = "${local.name_prefix}-failover-lambda"
  role     = aws_iam_role.failover_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets",
          "route53:GetChange",
          "route53:ListResourceRecordSets",
          "elasticloadbalancing:ModifyTargetGroup",
          "elasticloadbalancing:ModifyTargetGroupAttributes",
          "rds:PromoteReadReplica",
          "rds:DescribeDBClusters",
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "sns:Publish",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "failover_lambda_vpc" {
  provider   = aws.primary
  role       = aws_iam_role.failover_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Outputs
output "backup_vault_primary_arn" {
  description = "ARN of the primary backup vault"
  value       = aws_backup_vault.primary.arn
}

output "backup_vault_secondary_arn" {
  description = "ARN of the secondary backup vault"
  value       = aws_backup_vault.secondary.arn
}

output "dr_state_table_name" {
  description = "Name of the DynamoDB table for DR state management"
  value       = aws_dynamodb_table.dr_state.name
}

output "failover_lambda_arn" {
  description = "ARN of the failover orchestrator Lambda function"
  value       = aws_lambda_function.failover_orchestrator.arn
}

output "primary_health_check_id" {
  description = "ID of the primary endpoint health check"
  value       = aws_route53_health_check.primary.id
}

output "secondary_health_check_id" {
  description = "ID of the secondary endpoint health check"
  value       = aws_route53_health_check.secondary.id
}