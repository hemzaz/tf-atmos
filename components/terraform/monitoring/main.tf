resource "aws_cloudwatch_log_group" "main" {
  for_each = var.log_groups

  name              = "${var.tags["Environment"]}/${each.key}"
  retention_in_days = each.value.retention_days
  kms_key_id        = var.kms_key_id

  tags = merge(
    var.tags,
    {
      Name = "${var.tags["Environment"]}/${each.key}"
    }
  )
}

resource "aws_cloudwatch_dashboard" "main" {
  count = var.create_dashboard ? 1 : 0

  dashboard_name = "${var.tags["Environment"]}-dashboard"
  dashboard_body = templatefile(
    "${path.module}/templates/dashboard.json.tpl",
    {
      region               = var.region
      environment          = var.tags["Environment"]
      vpc_id               = var.vpc_id
      rds_instances        = var.rds_instances
      ecs_clusters         = var.ecs_clusters
      lambda_functions     = var.lambda_functions
      load_balancers       = var.load_balancers
      elasticache_clusters = var.elasticache_clusters
    }
  )
}

resource "aws_sns_topic" "alarms" {
  count = var.create_sns_topic ? 1 : 0

  name = "${var.tags["Environment"]}-alarms"

  tags = merge(
    var.tags,
    {
      Name = "${var.tags["Environment"]}-alarms"
    }
  )
}

resource "aws_sns_topic_subscription" "alarms_email" {
  count = var.create_sns_topic && length(var.alarm_email_subscriptions) > 0 ? length(var.alarm_email_subscriptions) : 0

  topic_arn = aws_sns_topic.alarms[0].arn
  protocol  = "email"
  endpoint  = var.alarm_email_subscriptions[count.index]
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  for_each = var.cpu_alarms

  alarm_name          = "${var.tags["Environment"]}-${each.key}-high-cpu"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = each.value.evaluation_periods
  metric_name         = "CPUUtilization"
  namespace           = each.value.namespace
  period              = each.value.period
  statistic           = "Average"
  threshold           = each.value.threshold
  alarm_description   = "High CPU utilization for ${each.key}"
  alarm_actions       = var.create_sns_topic ? [aws_sns_topic.alarms[0].arn] : []

  dimensions = each.value.dimensions

  tags = merge(
    var.tags,
    {
      Name = "${var.tags["Environment"]}-${each.key}-high-cpu"
    }
  )
}

resource "aws_cloudwatch_metric_alarm" "memory_high" {
  for_each = var.memory_alarms

  alarm_name          = "${var.tags["Environment"]}-${each.key}-high-memory"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = each.value.evaluation_periods
  metric_name         = "MemoryUtilization"
  namespace           = each.value.namespace
  period              = each.value.period
  statistic           = "Average"
  threshold           = each.value.threshold
  alarm_description   = "High memory utilization for ${each.key}"
  alarm_actions       = var.create_sns_topic ? [aws_sns_topic.alarms[0].arn] : []

  dimensions = each.value.dimensions

  tags = merge(
    var.tags,
    {
      Name = "${var.tags["Environment"]}-${each.key}-high-memory"
    }
  )
}

resource "aws_cloudwatch_metric_alarm" "db_connections_high" {
  for_each = var.db_connection_alarms

  alarm_name          = "${var.tags["Environment"]}-${each.key}-high-connections"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = each.value.evaluation_periods
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = each.value.period
  statistic           = "Average"
  threshold           = each.value.threshold
  alarm_description   = "High database connections for ${each.key}"
  alarm_actions       = var.create_sns_topic ? [aws_sns_topic.alarms[0].arn] : []

  dimensions = {
    DBInstanceIdentifier = each.key
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.tags["Environment"]}-${each.key}-high-connections"
    }
  )
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each = var.lambda_error_alarms

  alarm_name          = "${var.tags["Environment"]}-${each.key}-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = each.value.evaluation_periods
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = each.value.period
  statistic           = "Sum"
  threshold           = each.value.threshold
  alarm_description   = "Error count for Lambda function ${each.key}"
  alarm_actions       = var.create_sns_topic ? [aws_sns_topic.alarms[0].arn] : []

  dimensions = {
    FunctionName = each.key
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.tags["Environment"]}-${each.key}-errors"
    }
  )
}

# Create a CloudWatch Logs Metric Filter and Alarm for specific log patterns
resource "aws_cloudwatch_log_metric_filter" "error_logs" {
  for_each = var.log_metric_filters

  name           = "${var.tags["Environment"]}-${each.key}-errors"
  pattern        = each.value.pattern
  log_group_name = aws_cloudwatch_log_group.main[each.value.log_group_name].name

  metric_transformation {
    name      = "${var.tags["Environment"]}_${each.key}_errors"
    namespace = "CustomMetrics/${var.tags["Environment"]}"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "log_errors" {
  for_each = var.log_metric_filters

  alarm_name          = "${var.tags["Environment"]}-${each.key}-log-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = each.value.evaluation_periods
  metric_name         = "${var.tags["Environment"]}_${each.key}_errors"
  namespace           = "CustomMetrics/${var.tags["Environment"]}"
  period              = each.value.period
  statistic           = "Sum"
  threshold           = each.value.threshold
  alarm_description   = "Error logs detected for ${each.key}"
  alarm_actions       = var.create_sns_topic ? [aws_sns_topic.alarms[0].arn] : []

  tags = merge(
    var.tags,
    {
      Name = "${var.tags["Environment"]}-${each.key}-log-errors"
    }
  )
}

