##############################################
# Kinesis Data Stream
##############################################

resource "aws_kinesis_stream" "main" {
  name             = "${var.name_prefix}-stream"
  retention_period = var.retention_hours

  dynamic "stream_mode_details" {
    for_each = var.stream_mode == "ON_DEMAND" ? [1] : []
    content {
      stream_mode = "ON_DEMAND"
    }
  }

  shard_count = var.stream_mode == "PROVISIONED" ? var.shard_count : null

  dynamic "shard_level_metrics" {
    for_each = var.enable_enhanced_monitoring ? [1] : []
    content {
      shard_level_metrics = [
        "IncomingBytes",
        "IncomingRecords",
        "OutgoingBytes",
        "OutgoingRecords",
        "WriteProvisionedThroughputExceeded",
        "ReadProvisionedThroughputExceeded",
        "IteratorAgeMilliseconds"
      ]
    }
  }

  encryption_type = var.kms_key_id != null ? "KMS" : "NONE"
  kms_key_id      = var.kms_key_id

  tags = merge(
    var.tags,
    {
      Name      = "${var.name_prefix}-stream"
      Module    = "kinesis-stream"
      ManagedBy = "terraform"
    }
  )
}

##############################################
# Enhanced Fan-Out Consumers
##############################################

resource "aws_kinesis_stream_consumer" "main" {
  for_each = var.enhanced_fanout_consumers

  name       = each.value
  stream_arn = aws_kinesis_stream.main.arn
}

##############################################
# CloudWatch Log Group for Delivery
##############################################

resource "aws_cloudwatch_log_group" "stream" {
  count = var.enable_cloudwatch_logs ? 1 : 0

  name              = "/aws/kinesis/${var.name_prefix}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_id

  tags = merge(
    var.tags,
    {
      Name      = "${var.name_prefix}-kinesis-logs"
      ManagedBy = "terraform"
    }
  )
}

##############################################
# Lambda Event Source Mapping
##############################################

resource "aws_lambda_event_source_mapping" "consumer" {
  for_each = var.lambda_consumers

  event_source_arn                   = aws_kinesis_stream.main.arn
  function_name                      = each.value.function_name
  starting_position                  = lookup(each.value, "starting_position", "LATEST")
  batch_size                         = lookup(each.value, "batch_size", 100)
  maximum_batching_window_in_seconds = lookup(each.value, "batching_window", 0)
  parallelization_factor             = lookup(each.value, "parallelization_factor", 1)
  enabled                            = lookup(each.value, "enabled", true)

  dynamic "destination_config" {
    for_each = lookup(each.value, "on_failure_destination", null) != null ? [1] : []
    content {
      on_failure {
        destination_arn = each.value.on_failure_destination
      }
    }
  }

  dynamic "filter_criteria" {
    for_each = lookup(each.value, "filter_pattern", null) != null ? [1] : []
    content {
      filter {
        pattern = each.value.filter_pattern
      }
    }
  }
}

##############################################
# CloudWatch Alarms
##############################################

resource "aws_cloudwatch_metric_alarm" "iterator_age" {
  count = var.enable_monitoring ? 1 : 0

  alarm_name          = "${var.name_prefix}-iterator-age-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "GetRecords.IteratorAgeMilliseconds"
  namespace           = "AWS/Kinesis"
  period              = 300
  statistic           = "Maximum"
  threshold           = var.iterator_age_threshold_ms
  alarm_description   = "Iterator age is high, indicating processing lag"
  alarm_actions       = var.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    StreamName = aws_kinesis_stream.main.name
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "write_throttle" {
  count = var.enable_monitoring && var.stream_mode == "PROVISIONED" ? 1 : 0

  alarm_name          = "${var.name_prefix}-write-throttled"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "WriteProvisionedThroughputExceeded"
  namespace           = "AWS/Kinesis"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "Write operations are being throttled"
  alarm_actions       = var.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    StreamName = aws_kinesis_stream.main.name
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "read_throttle" {
  count = var.enable_monitoring && var.stream_mode == "PROVISIONED" ? 1 : 0

  alarm_name          = "${var.name_prefix}-read-throttled"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ReadProvisionedThroughputExceeded"
  namespace           = "AWS/Kinesis"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "Read operations are being throttled"
  alarm_actions       = var.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    StreamName = aws_kinesis_stream.main.name
  }

  tags = var.tags
}

##############################################
# Application Auto Scaling (for provisioned mode)
##############################################

resource "aws_appautoscaling_target" "stream" {
  count = var.enable_auto_scaling && var.stream_mode == "PROVISIONED" ? 1 : 0

  max_capacity       = var.max_shard_count
  min_capacity       = var.min_shard_count
  resource_id        = "stream/${aws_kinesis_stream.main.name}"
  scalable_dimension = "kinesis:stream:WriteCapacity"
  service_namespace  = "kinesis"
}

resource "aws_appautoscaling_policy" "stream_write" {
  count = var.enable_auto_scaling && var.stream_mode == "PROVISIONED" ? 1 : 0

  name               = "${var.name_prefix}-write-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.stream[0].resource_id
  scalable_dimension = aws_appautoscaling_target.stream[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.stream[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "KinesisStreamIncomingBytes"
    }
    target_value       = var.scaling_target_utilization
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}
