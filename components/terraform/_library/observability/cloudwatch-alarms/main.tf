##############################################
# SNS Topic for Alarms
##############################################

resource "aws_sns_topic" "alarms" {
  count = var.create_sns_topic ? 1 : 0

  name              = "${var.name_prefix}-alarms"
  display_name      = "CloudWatch Alarms - ${var.name_prefix}"
  kms_master_key_id = var.kms_key_id

  tags = merge(
    var.tags,
    {
      Name      = "${var.name_prefix}-alarms"
      ManagedBy = "terraform"
    }
  )
}

resource "aws_sns_topic_subscription" "email" {
  count = var.create_sns_topic && length(var.alarm_email_endpoints) > 0 ? length(var.alarm_email_endpoints) : 0

  topic_arn = aws_sns_topic.alarms[0].arn
  protocol  = "email"
  endpoint  = var.alarm_email_endpoints[count.index]
}

##############################################
# Standard Alarm Templates
##############################################

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  count = var.create_cpu_alarms ? 1 : 0

  alarm_name          = "${var.name_prefix}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.cpu_evaluation_periods
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = var.cpu_period
  statistic           = "Average"
  threshold           = var.cpu_threshold
  alarm_description   = "CPU utilization exceeds ${var.cpu_threshold}%"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.ok_actions

  tags = merge(
    var.tags,
    {
      Name     = "${var.name_prefix}-cpu-high"
      Severity = "high"
    }
  )
}

resource "aws_cloudwatch_metric_alarm" "memory_high" {
  count = var.create_memory_alarms ? 1 : 0

  alarm_name          = "${var.name_prefix}-memory-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.memory_evaluation_periods
  metric_name         = "mem_used_percent"
  namespace           = "CWAgent"
  period              = var.memory_period
  statistic           = "Average"
  threshold           = var.memory_threshold
  alarm_description   = "Memory utilization exceeds ${var.memory_threshold}%"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.ok_actions

  tags = merge(
    var.tags,
    {
      Name     = "${var.name_prefix}-memory-high"
      Severity = "high"
    }
  )
}

resource "aws_cloudwatch_metric_alarm" "disk_high" {
  count = var.create_disk_alarms ? 1 : 0

  alarm_name          = "${var.name_prefix}-disk-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.disk_evaluation_periods
  metric_name         = "disk_used_percent"
  namespace           = "CWAgent"
  period              = var.disk_period
  statistic           = "Average"
  threshold           = var.disk_threshold
  alarm_description   = "Disk utilization exceeds ${var.disk_threshold}%"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.ok_actions

  tags = merge(
    var.tags,
    {
      Name     = "${var.name_prefix}-disk-high"
      Severity = "high"
    }
  )
}

##############################################
# Anomaly Detection Alarms
##############################################

resource "aws_cloudwatch_metric_alarm" "anomaly_cpu" {
  count = var.enable_anomaly_detection ? 1 : 0

  alarm_name          = "${var.name_prefix}-cpu-anomaly"
  comparison_operator = "GreaterThanUpperThreshold"
  evaluation_periods  = 2
  threshold_metric_id = "e1"
  alarm_description   = "CPU anomaly detected"
  alarm_actions       = var.alarm_actions

  metric_query {
    id          = "e1"
    expression  = "ANOMALY_DETECTION_BAND(m1, ${var.anomaly_detection_band})"
    label       = "CPU Anomaly Detection"
    return_data = true
  }

  metric_query {
    id = "m1"
    metric {
      metric_name = "CPUUtilization"
      namespace   = "AWS/EC2"
      period      = 300
      stat        = "Average"
    }
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-cpu-anomaly"
      Type = "anomaly"
    }
  )
}

##############################################
# Composite Alarms
##############################################

resource "aws_cloudwatch_composite_alarm" "system_critical" {
  count = var.create_composite_alarms ? 1 : 0

  alarm_name          = "${var.name_prefix}-system-critical"
  alarm_description   = "Multiple system metrics in alarm state"
  actions_enabled     = true
  alarm_actions       = var.alarm_actions
  ok_actions          = var.ok_actions
  insufficient_data_actions = []

  alarm_rule = join(" OR ", [
    var.create_cpu_alarms ? "ALARM(${aws_cloudwatch_metric_alarm.cpu_high[0].alarm_name})" : "",
    var.create_memory_alarms ? "ALARM(${aws_cloudwatch_metric_alarm.memory_high[0].alarm_name})" : "",
    var.create_disk_alarms ? "ALARM(${aws_cloudwatch_metric_alarm.disk_high[0].alarm_name})" : ""
  ])

  tags = merge(
    var.tags,
    {
      Name     = "${var.name_prefix}-system-critical"
      Type     = "composite"
      Severity = "critical"
    }
  )
}

##############################################
# Custom Alarms
##############################################

resource "aws_cloudwatch_metric_alarm" "custom" {
  for_each = var.custom_alarms

  alarm_name          = "${var.name_prefix}-${each.key}"
  comparison_operator = each.value.comparison_operator
  evaluation_periods  = each.value.evaluation_periods
  metric_name         = each.value.metric_name
  namespace           = each.value.namespace
  period              = each.value.period
  statistic           = each.value.statistic
  threshold           = each.value.threshold
  alarm_description   = each.value.description
  alarm_actions       = var.alarm_actions
  ok_actions          = var.ok_actions
  treat_missing_data  = lookup(each.value, "treat_missing_data", "notBreaching")

  dynamic "dimensions" {
    for_each = lookup(each.value, "dimensions", {})
    content {
      name  = dimensions.key
      value = dimensions.value
    }
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-${each.key}"
    }
  )
}

##############################################
# Auto-Remediation Lambda
##############################################

resource "aws_lambda_function" "auto_remediation" {
  count = var.enable_auto_remediation ? 1 : 0

  filename      = "${path.module}/templates/auto_remediation.zip"
  function_name = "${var.name_prefix}-auto-remediation"
  role          = aws_iam_role.auto_remediation[0].arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 60

  environment {
    variables = {
      SLACK_WEBHOOK_URL = var.slack_webhook_url
      ENABLED_ACTIONS   = jsonencode(var.auto_remediation_actions)
    }
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-auto-remediation"
    }
  )
}

resource "aws_lambda_permission" "cloudwatch" {
  count = var.enable_auto_remediation ? 1 : 0

  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.auto_remediation[0].function_name
  principal     = "cloudwatch.amazonaws.com"
}

resource "aws_iam_role" "auto_remediation" {
  count = var.enable_auto_remediation ? 1 : 0

  name = "${var.name_prefix}-auto-remediation"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "auto_remediation" {
  count = var.enable_auto_remediation ? 1 : 0

  name = "${var.name_prefix}-auto-remediation-policy"
  role = aws_iam_role.auto_remediation[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:StopInstances",
          "ec2:RebootInstances",
          "autoscaling:SetDesiredCapacity"
        ]
        Resource = "*"
      }
    ]
  })
}

##############################################
# Data Sources
##############################################

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
