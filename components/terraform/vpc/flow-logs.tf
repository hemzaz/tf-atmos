# VPC Flow Logs for network traffic monitoring and security analysis
# Captures ALL traffic (ACCEPT and REJECT) with comprehensive logging

locals {
  # The caller's key when supplied (kms/main, whose allow_cloudwatch_logs
  # already grants every log group in this account and region), otherwise
  # this component's own key.
  flow_logs_kms_key_arn = var.flow_logs_kms_key_arn != "" ? var.flow_logs_kms_key_arn : one(aws_kms_key.flow_logs[*].arn)
}

# KMS key for CloudWatch Logs encryption, created only when the caller
# supplies none of its own: with a caller key, this key would otherwise sit
# unused (the log group and, if flow_logs_s3_backup is enabled, the archive
# bucket both use local.flow_logs_kms_key_arn instead).
resource "aws_kms_key" "flow_logs" {
  count = var.vpc_flow_logs_enabled && var.flow_logs_kms_key_arn == "" ? 1 : 0

  description             = "KMS key for VPC Flow Logs encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  # Account administration plus CloudWatch Logs, which cannot use the key without a grant
  # here. A key policy cannot reference its own ARN; "*" means "this key". With
  # flow_logs_s3_backup, also the log delivery service that writes the S3 copy into
  # the SSE-KMS archive bucket: kms:GenerateDataKey* only, as kms/main's
  # allow_log_delivery grants it.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Sid       = "EnableAccountAdministration"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowCloudWatchLogsFlowLogGroups"
        Effect    = "Allow"
        Principal = { Service = "logs.${var.region}.amazonaws.com" }
        Action = [
          "kms:Encrypt*",
          "kms:Decrypt*",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:Describe*",
        ]
        Resource = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/vpc/flowlogs/*"
          }
        }
      },
      ], var.flow_logs_s3_backup ? [
      {
        Sid       = "AllowLogDeliveryS3Archive"
        Effect    = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action    = "kms:GenerateDataKey*"
        Resource  = "*"
        Condition = {
          StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
          ArnLike      = { "aws:SourceArn" = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:*" }
        }
      },
    ] : [])
  })

  tags = merge(
    var.tags,
    {
      Name    = "${var.tags["Environment"]}-vpc-flow-logs-kms"
      Purpose = "vpc-flow-logs-encryption"
    }
  )
}

resource "aws_kms_alias" "flow_logs" {
  count = var.vpc_flow_logs_enabled && var.flow_logs_kms_key_arn == "" ? 1 : 0

  name          = "alias/${var.tags["Environment"]}-vpc-flow-logs"
  target_key_id = aws_kms_key.flow_logs[0].key_id
}

# CloudWatch Log Group for Flow Logs
resource "aws_cloudwatch_log_group" "flow_logs" {
  #checkov:skip=CKV_AWS_338:CloudWatch retention is var.flow_logs_retention_days (default 30), a per-stack cost decision; set flow_logs_s3_backup for a year in S3 (aws_flow_log.s3)
  count = var.vpc_flow_logs_enabled ? 1 : 0

  name              = "/aws/vpc/flowlogs/${aws_vpc.main.id}"
  retention_in_days = var.flow_logs_retention_days
  kms_key_id        = local.flow_logs_kms_key_arn

  tags = merge(
    var.tags,
    {
      Name        = "${var.tags["Environment"]}-vpc-flow-logs"
      Purpose     = "vpc-network-monitoring"
      Environment = var.tags["Environment"]
    }
  )
}

# IAM Role for Flow Logs
resource "aws_iam_role" "flow_logs" {
  count = var.vpc_flow_logs_enabled ? 1 : 0

  name = "${var.tags["Environment"]}-vpc-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
        Action = "sts:AssumeRole"
        # Confused-deputy guard, as AWS documents for this role
        # (https://docs.aws.amazon.com/vpc/latest/userguide/flow-logs-iam-role.html):
        # source account = the flow log's owner, source ARN = a flow log in
        # this account and region. The flow log ID does not exist until the
        # flow log is created with this role, hence the documented wildcard.
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
          ArnLike = {
            "aws:SourceArn" = "arn:aws:ec2:${var.region}:${data.aws_caller_identity.current.account_id}:vpc-flow-log/*"
          }
        }
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name    = "${var.tags["Environment"]}-vpc-flow-logs-role"
      Purpose = "vpc-flow-logs-service-role"
    }
  )
}

# IAM Policy for Flow Logs to write to CloudWatch
resource "aws_iam_role_policy" "flow_logs" {
  count = var.vpc_flow_logs_enabled ? 1 : 0

  name = "${var.tags["Environment"]}-vpc-flow-logs-policy"
  role = aws_iam_role.flow_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "${aws_cloudwatch_log_group.flow_logs[0].arn}:*"
      }
    ]
  })
}

# VPC Flow Log resource
resource "aws_flow_log" "main" {
  count = var.vpc_flow_logs_enabled ? 1 : 0

  vpc_id                   = aws_vpc.main.id
  traffic_type             = var.vpc_flow_logs_traffic_type
  iam_role_arn             = aws_iam_role.flow_logs[0].arn
  log_destination_type     = "cloud-watch-logs"
  log_destination          = aws_cloudwatch_log_group.flow_logs[0].arn
  max_aggregation_interval = var.vpc_flow_logs_max_aggregation_interval

  # Custom log format for detailed analysis
  log_format = var.vpc_flow_logs_format != null ? var.vpc_flow_logs_format : "$${version} $${account-id} $${interface-id} $${srcaddr} $${dstaddr} $${srcport} $${dstport} $${protocol} $${packets} $${bytes} $${start} $${end} $${action} $${log-status}"

  tags = merge(
    var.tags,
    {
      Name        = "${var.tags["Environment"]}-vpc-flow-log"
      Purpose     = "network-traffic-monitoring"
      TrafficType = "ALL"
    }
  )
}

# CloudWatch Metric Filters for Security Events

# 1. SSH access attempts
resource "aws_cloudwatch_log_metric_filter" "ssh_access" {
  count = var.vpc_flow_logs_enabled && var.enable_flow_logs_alarms ? 1 : 0

  name           = "${var.tags["Environment"]}-ssh-access-attempts"
  log_group_name = aws_cloudwatch_log_group.flow_logs[0].name
  pattern        = "[version, account, eni, source, destination, srcport, dstport=\"22\", protocol=\"6\", packets, bytes, windowstart, windowend, action, flowlogstatus]"

  metric_transformation {
    name          = "SSHAccessAttempts"
    namespace     = "VPC/FlowLogs"
    value         = "1"
    default_value = "0"
    unit          = "Count"
  }
}

resource "aws_cloudwatch_metric_alarm" "ssh_access" {
  count = var.vpc_flow_logs_enabled && var.enable_flow_logs_alarms ? 1 : 0

  alarm_name          = "${var.tags["Environment"]}-high-ssh-access-attempts"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "SSHAccessAttempts"
  namespace           = "VPC/FlowLogs"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.ssh_access_alarm_threshold
  alarm_description   = "Alert on high SSH access attempts"
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.flow_logs_alarm_actions
}

# 2. RDP access attempts
resource "aws_cloudwatch_log_metric_filter" "rdp_access" {
  count = var.vpc_flow_logs_enabled && var.enable_flow_logs_alarms ? 1 : 0

  name           = "${var.tags["Environment"]}-rdp-access-attempts"
  log_group_name = aws_cloudwatch_log_group.flow_logs[0].name
  pattern        = "[version, account, eni, source, destination, srcport, dstport=\"3389\", protocol=\"6\", packets, bytes, windowstart, windowend, action, flowlogstatus]"

  metric_transformation {
    name          = "RDPAccessAttempts"
    namespace     = "VPC/FlowLogs"
    value         = "1"
    default_value = "0"
    unit          = "Count"
  }
}

resource "aws_cloudwatch_metric_alarm" "rdp_access" {
  count = var.vpc_flow_logs_enabled && var.enable_flow_logs_alarms ? 1 : 0

  alarm_name          = "${var.tags["Environment"]}-high-rdp-access-attempts"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "RDPAccessAttempts"
  namespace           = "VPC/FlowLogs"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.rdp_access_alarm_threshold
  alarm_description   = "Alert on high RDP access attempts"
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.flow_logs_alarm_actions
}

# 3. Rejected connection attempts
resource "aws_cloudwatch_log_metric_filter" "rejected_connections" {
  count = var.vpc_flow_logs_enabled && var.enable_flow_logs_alarms ? 1 : 0

  name           = "${var.tags["Environment"]}-rejected-connections"
  log_group_name = aws_cloudwatch_log_group.flow_logs[0].name
  pattern        = "[version, account, eni, source, destination, srcport, dstport, protocol, packets, bytes, windowstart, windowend, action=\"REJECT\", flowlogstatus]"

  metric_transformation {
    name          = "RejectedConnections"
    namespace     = "VPC/FlowLogs"
    value         = "1"
    default_value = "0"
    unit          = "Count"
  }
}

resource "aws_cloudwatch_metric_alarm" "rejected_connections" {
  count = var.vpc_flow_logs_enabled && var.enable_flow_logs_alarms ? 1 : 0

  alarm_name          = "${var.tags["Environment"]}-high-rejected-connections"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "RejectedConnections"
  namespace           = "VPC/FlowLogs"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.rejected_connections_alarm_threshold
  alarm_description   = "Alert on high number of rejected connections (potential attack)"
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.flow_logs_alarm_actions
}

# 4. Large data transfers (potential data exfiltration)
resource "aws_cloudwatch_log_metric_filter" "large_data_transfer" {
  count = var.vpc_flow_logs_enabled && var.enable_flow_logs_alarms ? 1 : 0

  name           = "${var.tags["Environment"]}-large-data-transfers"
  log_group_name = aws_cloudwatch_log_group.flow_logs[0].name
  pattern        = "[version, account, eni, source, destination, srcport, dstport, protocol, packets, bytes > 10000000, windowstart, windowend, action, flowlogstatus]"

  metric_transformation {
    name          = "LargeDataTransfers"
    namespace     = "VPC/FlowLogs"
    value         = "$bytes"
    default_value = "0"
    unit          = "Bytes"
  }
}

resource "aws_cloudwatch_metric_alarm" "large_data_transfer" {
  count = var.vpc_flow_logs_enabled && var.enable_flow_logs_alarms ? 1 : 0

  alarm_name          = "${var.tags["Environment"]}-large-data-transfers"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "LargeDataTransfers"
  namespace           = "VPC/FlowLogs"
  period              = "900"
  statistic           = "Sum"
  threshold           = var.large_data_transfer_alarm_threshold
  alarm_description   = "Alert on large data transfers (potential data exfiltration)"
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.flow_logs_alarm_actions
}

# 5. Port scanning detection (many different ports from same source)
resource "aws_cloudwatch_log_metric_filter" "port_scan" {
  count = var.vpc_flow_logs_enabled && var.enable_flow_logs_alarms ? 1 : 0

  name           = "${var.tags["Environment"]}-port-scan-activity"
  log_group_name = aws_cloudwatch_log_group.flow_logs[0].name
  # This pattern detects multiple rejected connection attempts
  pattern = "[version, account, eni, source, destination, srcport, dstport, protocol, packets=\"1\", bytes, windowstart, windowend, action=\"REJECT\", flowlogstatus]"

  metric_transformation {
    name          = "PortScanActivity"
    namespace     = "VPC/FlowLogs"
    value         = "1"
    default_value = "0"
    unit          = "Count"
  }
}

resource "aws_cloudwatch_metric_alarm" "port_scan" {
  count = var.vpc_flow_logs_enabled && var.enable_flow_logs_alarms ? 1 : 0

  alarm_name          = "${var.tags["Environment"]}-port-scan-detected"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "PortScanActivity"
  namespace           = "VPC/FlowLogs"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.port_scan_alarm_threshold
  alarm_description   = "Alert on potential port scanning activity"
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.flow_logs_alarm_actions
}

# Optional: S3 bucket for long-term Flow Logs storage
resource "aws_s3_bucket" "flow_logs" {
  #checkov:skip=CKV2_AWS_6:False positive, aws_s3_bucket_public_access_block.flow_logs covers this bucket
  #checkov:skip=CKV2_AWS_61:False positive, aws_s3_bucket_lifecycle_configuration.flow_logs covers this bucket
  #checkov:skip=CKV_AWS_21:False positive, aws_s3_bucket_versioning.flow_logs covers this bucket
  #checkov:skip=CKV_AWS_145:False positive, aws_s3_bucket_server_side_encryption_configuration.flow_logs uses the flow logs CMK
  #checkov:skip=CKV_AWS_18:This bucket is a log archive; access logs of a log bucket are out of scope (as alb's access_logs bucket)
  #checkov:skip=CKV_AWS_144:Log archive; cross-region replication is out of scope (as alb's access_logs bucket)
  #checkov:skip=CKV2_AWS_62:Nothing consumes object-created notifications on a log archive
  count = var.vpc_flow_logs_enabled && var.flow_logs_s3_backup ? 1 : 0

  bucket = "${var.tags["Environment"]}-vpc-flow-logs-${data.aws_caller_identity.current.account_id}"

  tags = merge(
    var.tags,
    {
      Name    = "${var.tags["Environment"]}-vpc-flow-logs-archive"
      Purpose = "flow-logs-long-term-storage"
    }
  )
}

resource "aws_s3_bucket_versioning" "flow_logs" {
  count = var.vpc_flow_logs_enabled && var.flow_logs_s3_backup ? 1 : 0

  bucket = aws_s3_bucket.flow_logs[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "flow_logs" {
  count = var.vpc_flow_logs_enabled && var.flow_logs_s3_backup ? 1 : 0

  bucket = aws_s3_bucket.flow_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = local.flow_logs_kms_key_arn
    }
  }
}

resource "aws_s3_bucket_public_access_block" "flow_logs" {
  count = var.vpc_flow_logs_enabled && var.flow_logs_s3_backup ? 1 : 0

  bucket = aws_s3_bucket.flow_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "flow_logs" {
  count = var.vpc_flow_logs_enabled && var.flow_logs_s3_backup ? 1 : 0

  bucket = aws_s3_bucket.flow_logs[0].id

  rule {
    id     = "flow-logs-lifecycle"
    status = "Enabled"

    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 180
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Lets the log delivery service write the S3 copy, as Cloud Posse's
# vpc-flow-logs-s3-bucket does (AWSLogDeliveryWrite / AWSLogDeliveryAclCheck,
# scoped to this account), plus TLS-only access. AWS's policy also requires
# s3:x-amz-acl = bucket-owner-full-control; it is left out because the bucket
# keeps S3's default BucketOwnerEnforced ownership, so ACLs are disabled and
# the condition adds nothing.
data "aws_iam_policy_document" "flow_logs_bucket" {
  count = var.vpc_flow_logs_enabled && var.flow_logs_s3_backup ? 1 : 0

  statement {
    sid       = "AWSLogDeliveryWrite"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.flow_logs[0].arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:*"]
    }
  }

  statement {
    sid       = "AWSLogDeliveryAclCheck"
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.flow_logs[0].arn]

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:*"]
    }
  }

  statement {
    sid       = "ForceSSLOnlyAccess"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.flow_logs[0].arn, "${aws_s3_bucket.flow_logs[0].arn}/*"]

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

resource "aws_s3_bucket_policy" "flow_logs" {
  count = var.vpc_flow_logs_enabled && var.flow_logs_s3_backup ? 1 : 0

  bucket = aws_s3_bucket.flow_logs[0].id
  policy = data.aws_iam_policy_document.flow_logs_bucket[0].json

  depends_on = [aws_s3_bucket_public_access_block.flow_logs]
}

# The long-term copy: a second flow log of the same VPC and traffic into the
# archive bucket (90 days Standard, then IA, Glacier, expiry at 365). S3
# destinations need no IAM role; delivery.logs.amazonaws.com writes under the
# bucket policy above and encrypts with local.flow_logs_kms_key_arn.
resource "aws_flow_log" "s3" {
  count = var.vpc_flow_logs_enabled && var.flow_logs_s3_backup ? 1 : 0

  vpc_id                   = aws_vpc.main.id
  traffic_type             = var.vpc_flow_logs_traffic_type
  log_destination_type     = "s3"
  log_destination          = aws_s3_bucket.flow_logs[0].arn
  max_aggregation_interval = var.vpc_flow_logs_max_aggregation_interval
  log_format               = aws_flow_log.main[0].log_format

  tags = merge(
    var.tags,
    {
      Name        = "${var.tags["Environment"]}-vpc-flow-log-s3"
      Purpose     = "network-traffic-archive"
      TrafficType = var.vpc_flow_logs_traffic_type
    }
  )

  depends_on = [aws_s3_bucket_policy.flow_logs]
}

# Data source for current account ID
data "aws_caller_identity" "current" {}
