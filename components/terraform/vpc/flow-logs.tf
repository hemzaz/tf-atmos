# VPC Flow Logs for network traffic monitoring and security analysis
# Captures ALL traffic (ACCEPT and REJECT) with comprehensive logging

# KMS key for CloudWatch Logs encryption
resource "aws_kms_key" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  description             = "KMS key for VPC Flow Logs encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = merge(
    var.tags,
    {
      Name    = "${var.tags["Environment"]}-vpc-flow-logs-kms"
      Purpose = "vpc-flow-logs-encryption"
    }
  )
}

resource "aws_kms_alias" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name          = "alias/${var.tags["Environment"]}-vpc-flow-logs"
  target_key_id = aws_kms_key.flow_logs[0].key_id
}

# CloudWatch Log Group for Flow Logs
resource "aws_cloudwatch_log_group" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name              = "/aws/vpc/flowlogs/${aws_vpc.main.id}"
  retention_in_days = var.flow_logs_retention_days
  kms_key_id        = aws_kms_key.flow_logs[0].arn

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
  count = var.enable_flow_logs ? 1 : 0

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
  count = var.enable_flow_logs ? 1 : 0

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
  count = var.enable_flow_logs ? 1 : 0

  vpc_id                   = aws_vpc.main.id
  traffic_type             = "ALL"
  iam_role_arn            = aws_iam_role.flow_logs[0].arn
  log_destination_type    = "cloud-watch-logs"
  log_destination         = aws_cloudwatch_log_group.flow_logs[0].arn
  max_aggregation_interval = var.flow_logs_aggregation_interval

  # Custom log format for detailed analysis
  log_format = var.flow_logs_custom_format != null ? var.flow_logs_custom_format : "$${version} $${account-id} $${interface-id} $${srcaddr} $${dstaddr} $${srcport} $${dstport} $${protocol} $${packets} $${bytes} $${start} $${end} $${action} $${log-status}"

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
  count = var.enable_flow_logs && var.enable_flow_logs_alarms ? 1 : 0

  name           = "${var.tags["Environment"]}-ssh-access-attempts"
  log_group_name = aws_cloudwatch_log_group.flow_logs[0].name
  pattern        = "[version, account, eni, source, destination, srcport, dstport=\"22\", protocol=\"6\", packets, bytes, windowstart, windowend, action, flowlogstatus]"

  metric_transformation {
    name      = "SSHAccessAttempts"
    namespace = "VPC/FlowLogs"
    value     = "1"
    default_value = "0"
    unit      = "Count"
  }
}

resource "aws_cloudwatch_metric_alarm" "ssh_access" {
  count = var.enable_flow_logs && var.enable_flow_logs_alarms ? 1 : 0

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

  tags = var.tags
}

# 2. RDP access attempts
resource "aws_cloudwatch_log_metric_filter" "rdp_access" {
  count = var.enable_flow_logs && var.enable_flow_logs_alarms ? 1 : 0

  name           = "${var.tags["Environment"]}-rdp-access-attempts"
  log_group_name = aws_cloudwatch_log_group.flow_logs[0].name
  pattern        = "[version, account, eni, source, destination, srcport, dstport=\"3389\", protocol=\"6\", packets, bytes, windowstart, windowend, action, flowlogstatus]"

  metric_transformation {
    name      = "RDPAccessAttempts"
    namespace = "VPC/FlowLogs"
    value     = "1"
    default_value = "0"
    unit      = "Count"
  }
}

resource "aws_cloudwatch_metric_alarm" "rdp_access" {
  count = var.enable_flow_logs && var.enable_flow_logs_alarms ? 1 : 0

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

  tags = var.tags
}

# 3. Rejected connection attempts
resource "aws_cloudwatch_log_metric_filter" "rejected_connections" {
  count = var.enable_flow_logs && var.enable_flow_logs_alarms ? 1 : 0

  name           = "${var.tags["Environment"]}-rejected-connections"
  log_group_name = aws_cloudwatch_log_group.flow_logs[0].name
  pattern        = "[version, account, eni, source, destination, srcport, dstport, protocol, packets, bytes, windowstart, windowend, action=\"REJECT\", flowlogstatus]"

  metric_transformation {
    name      = "RejectedConnections"
    namespace = "VPC/FlowLogs"
    value     = "1"
    default_value = "0"
    unit      = "Count"
  }
}

resource "aws_cloudwatch_metric_alarm" "rejected_connections" {
  count = var.enable_flow_logs && var.enable_flow_logs_alarms ? 1 : 0

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

  tags = var.tags
}

# 4. Large data transfers (potential data exfiltration)
resource "aws_cloudwatch_log_metric_filter" "large_data_transfer" {
  count = var.enable_flow_logs && var.enable_flow_logs_alarms ? 1 : 0

  name           = "${var.tags["Environment"]}-large-data-transfers"
  log_group_name = aws_cloudwatch_log_group.flow_logs[0].name
  pattern        = "[version, account, eni, source, destination, srcport, dstport, protocol, packets, bytes > 10000000, windowstart, windowend, action, flowlogstatus]"

  metric_transformation {
    name      = "LargeDataTransfers"
    namespace = "VPC/FlowLogs"
    value     = "$bytes"
    default_value = "0"
    unit      = "Bytes"
  }
}

resource "aws_cloudwatch_metric_alarm" "large_data_transfer" {
  count = var.enable_flow_logs && var.enable_flow_logs_alarms ? 1 : 0

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

  tags = var.tags
}

# 5. Port scanning detection (many different ports from same source)
resource "aws_cloudwatch_log_metric_filter" "port_scan" {
  count = var.enable_flow_logs && var.enable_flow_logs_alarms ? 1 : 0

  name           = "${var.tags["Environment"]}-port-scan-activity"
  log_group_name = aws_cloudwatch_log_group.flow_logs[0].name
  # This pattern detects multiple rejected connection attempts
  pattern        = "[version, account, eni, source, destination, srcport, dstport, protocol, packets=\"1\", bytes, windowstart, windowend, action=\"REJECT\", flowlogstatus]"

  metric_transformation {
    name      = "PortScanActivity"
    namespace = "VPC/FlowLogs"
    value     = "1"
    default_value = "0"
    unit      = "Count"
  }
}

resource "aws_cloudwatch_metric_alarm" "port_scan" {
  count = var.enable_flow_logs && var.enable_flow_logs_alarms ? 1 : 0

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

  tags = var.tags
}

# Optional: S3 bucket for long-term Flow Logs storage
resource "aws_s3_bucket" "flow_logs" {
  count = var.enable_flow_logs && var.flow_logs_s3_backup ? 1 : 0

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
  count = var.enable_flow_logs && var.flow_logs_s3_backup ? 1 : 0

  bucket = aws_s3_bucket.flow_logs[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "flow_logs" {
  count = var.enable_flow_logs && var.flow_logs_s3_backup ? 1 : 0

  bucket = aws_s3_bucket.flow_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.flow_logs[0].arn
    }
  }
}

resource "aws_s3_bucket_public_access_block" "flow_logs" {
  count = var.enable_flow_logs && var.flow_logs_s3_backup ? 1 : 0

  bucket = aws_s3_bucket.flow_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "flow_logs" {
  count = var.enable_flow_logs && var.flow_logs_s3_backup ? 1 : 0

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
  }
}

# Data source for current account ID
data "aws_caller_identity" "current" {}
