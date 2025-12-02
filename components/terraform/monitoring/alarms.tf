# Additional comprehensive alarms for production readiness

# RDS Storage Space Alarms
resource "aws_cloudwatch_metric_alarm" "rds_storage_low" {
  for_each = var.enable_rds_monitoring ? toset(var.rds_instances) : []

  alarm_name          = "${local.name_prefix}-rds-${each.value}-storage-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = var.rds_storage_threshold # bytes (20% of allocated storage)
  alarm_description   = "RDS instance ${each.value} has low free storage space"
  alarm_actions       = var.create_sns_topic ? [aws_sns_topic.alarms[0].arn] : []
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = each.value
  }

  tags = var.tags
}

# RDS CPU Utilization Alarms
resource "aws_cloudwatch_metric_alarm" "rds_cpu_high" {
  for_each = var.enable_rds_monitoring ? toset(var.rds_instances) : []

  alarm_name          = "${local.name_prefix}-rds-${each.value}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = var.rds_cpu_threshold
  alarm_description   = "RDS instance ${each.value} has high CPU utilization"
  alarm_actions       = var.create_sns_topic ? [aws_sns_topic.alarms[0].arn] : []

  dimensions = {
    DBInstanceIdentifier = each.value
  }

  tags = var.tags
}

# Lambda Throttles Alarm
resource "aws_cloudwatch_metric_alarm" "lambda_throttles" {
  for_each = var.lambda_throttle_monitoring ? toset(var.lambda_functions) : []

  alarm_name          = "${local.name_prefix}-lambda-${each.value}-throttles"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Throttles"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "Lambda function ${each.value} is being throttled"
  alarm_actions       = var.create_sns_topic ? [aws_sns_topic.alarms[0].arn] : []

  dimensions = {
    FunctionName = each.value
  }

  tags = var.tags
}

# Lambda Duration Alarm (timeout warning)
resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  for_each = var.lambda_duration_monitoring ? toset(var.lambda_functions) : []

  alarm_name          = "${local.name_prefix}-lambda-${each.value}-duration"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Average"
  threshold           = var.lambda_duration_threshold # milliseconds
  alarm_description   = "Lambda function ${each.value} has high execution duration"
  alarm_actions       = var.create_sns_topic ? [aws_sns_topic.alarms[0].arn] : []

  dimensions = {
    FunctionName = each.value
  }

  tags = var.tags
}

# EC2 Instance Status Check Failed
resource "aws_cloudwatch_metric_alarm" "ec2_status_check" {
  for_each = var.enable_ec2_monitoring ? toset(var.ec2_instance_ids) : []

  alarm_name          = "${local.name_prefix}-ec2-${each.value}-status-check"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = "60"
  statistic           = "Maximum"
  threshold           = "0"
  alarm_description   = "EC2 instance ${each.value} status check failed"
  alarm_actions       = var.create_sns_topic ? [aws_sns_topic.alarms[0].arn] : []

  dimensions = {
    InstanceId = each.value
  }

  tags = var.tags
}

# EKS Node Not Ready
resource "aws_cloudwatch_metric_alarm" "eks_node_not_ready" {
  count = var.enable_backend_monitoring && var.eks_cluster_name != null ? 1 : 0

  alarm_name          = "${local.name_prefix}-eks-node-not-ready"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "cluster_node_count"
  namespace           = "ContainerInsights"
  period              = "300"
  statistic           = "Average"
  threshold           = var.eks_min_node_count
  alarm_description   = "EKS cluster ${var.eks_cluster_name} has nodes in NotReady state"
  alarm_actions       = var.create_sns_topic ? [aws_sns_topic.alarms[0].arn] : []

  dimensions = {
    ClusterName = var.eks_cluster_name
  }

  tags = var.tags
}

# API Gateway 4XX Errors
resource "aws_cloudwatch_metric_alarm" "api_gateway_4xx_errors" {
  for_each = var.enable_backend_monitoring && length(var.api_gateway_stages) > 0 ? toset(var.api_gateway_stages) : []

  alarm_name          = "${local.name_prefix}-api-gateway-${each.value}-4xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "4XXError"
  namespace           = "AWS/ApiGateway"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.api_gateway_4xx_threshold
  alarm_description   = "API Gateway ${each.value} has high 4XX error rate"
  alarm_actions       = var.create_sns_topic ? [aws_sns_topic.alarms[0].arn] : []

  dimensions = {
    ApiName = var.api_gateway_name
    Stage   = each.value
  }

  tags = var.tags
}

# NAT Gateway Packets Drop Count
resource "aws_cloudwatch_metric_alarm" "nat_gateway_packets_drop" {
  for_each = var.enable_network_monitoring ? toset(var.nat_gateway_ids) : []

  alarm_name          = "${local.name_prefix}-nat-gateway-${each.value}-packets-drop"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "PacketsDropCount"
  namespace           = "AWS/NATGateway"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.nat_gateway_drop_threshold
  alarm_description   = "NAT Gateway ${each.value} is dropping packets"
  alarm_actions       = var.create_sns_topic ? [aws_sns_topic.alarms[0].arn] : []

  dimensions = {
    NatGatewayId = each.value
  }

  tags = var.tags
}

# VPC Flow Logs Delivery Failures
resource "aws_cloudwatch_metric_alarm" "flow_logs_delivery_failure" {
  count = var.enable_network_monitoring && var.vpc_id != "" ? 1 : 0

  alarm_name          = "${local.name_prefix}-vpc-flow-logs-delivery-failure"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "DeliveryFailures"
  namespace           = "AWS/VPC"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "VPC Flow Logs delivery failures detected"
  alarm_actions       = var.create_sns_topic ? [aws_sns_topic.alarms[0].arn] : []
  treat_missing_data  = "notBreaching"

  tags = var.tags
}

# Application ELB Target Response Time
resource "aws_cloudwatch_metric_alarm" "alb_target_response_time_p99" {
  for_each = var.enable_backend_monitoring && var.enable_percentile_alarms ? toset(var.load_balancers) : []

  alarm_name          = "${local.name_prefix}-alb-${each.value}-p99-response-time"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "3"
  threshold           = var.alb_p99_response_time_threshold
  alarm_description   = "ALB ${each.value} P99 response time is too high"
  alarm_actions       = var.create_sns_topic ? [aws_sns_topic.alarms[0].arn] : []

  metric_query {
    id          = "m1"
    return_data = true

    metric {
      metric_name = "TargetResponseTime"
      namespace   = "AWS/ApplicationELB"
      period      = "300"
      stat        = "p99"
      dimensions = {
        LoadBalancer = each.value
      }
    }
  }

  tags = var.tags
}

# ECS Service CPU Utilization
resource "aws_cloudwatch_metric_alarm" "ecs_service_cpu" {
  for_each = var.enable_ecs_monitoring ? var.ecs_services : {}

  alarm_name          = "${local.name_prefix}-ecs-${each.key}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "300"
  statistic           = "Average"
  threshold           = var.ecs_cpu_threshold
  alarm_description   = "ECS service ${each.key} has high CPU utilization"
  alarm_actions       = var.create_sns_topic ? [aws_sns_topic.alarms[0].arn] : []

  dimensions = {
    ClusterName = each.value.cluster_name
    ServiceName = each.value.service_name
  }

  tags = var.tags
}

# ECS Service Memory Utilization
resource "aws_cloudwatch_metric_alarm" "ecs_service_memory" {
  for_each = var.enable_ecs_monitoring ? var.ecs_services : {}

  alarm_name          = "${local.name_prefix}-ecs-${each.key}-memory-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = "300"
  statistic           = "Average"
  threshold           = var.ecs_memory_threshold
  alarm_description   = "ECS service ${each.key} has high memory utilization"
  alarm_actions       = var.create_sns_topic ? [aws_sns_topic.alarms[0].arn] : []

  dimensions = {
    ClusterName = each.value.cluster_name
    ServiceName = each.value.service_name
  }

  tags = var.tags
}

# DynamoDB Throttled Requests
resource "aws_cloudwatch_metric_alarm" "dynamodb_throttled_requests" {
  for_each = var.enable_dynamodb_monitoring ? toset(var.dynamodb_tables) : []

  alarm_name          = "${local.name_prefix}-dynamodb-${each.value}-throttled"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "UserErrors"
  namespace           = "AWS/DynamoDB"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.dynamodb_throttle_threshold
  alarm_description   = "DynamoDB table ${each.value} has throttled requests"
  alarm_actions       = var.create_sns_topic ? [aws_sns_topic.alarms[0].arn] : []

  dimensions = {
    TableName = each.value
  }

  tags = var.tags
}

# SQS Queue Message Age
resource "aws_cloudwatch_metric_alarm" "sqs_message_age" {
  for_each = var.enable_sqs_monitoring ? toset(var.sqs_queue_names) : []

  alarm_name          = "${local.name_prefix}-sqs-${each.value}-message-age"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ApproximateAgeOfOldestMessage"
  namespace           = "AWS/SQS"
  period              = "300"
  statistic           = "Maximum"
  threshold           = var.sqs_message_age_threshold # seconds
  alarm_description   = "SQS queue ${each.value} has old messages"
  alarm_actions       = var.create_sns_topic ? [aws_sns_topic.alarms[0].arn] : []

  dimensions = {
    QueueName = each.value
  }

  tags = var.tags
}

# Anomaly Detection Based Alarms
resource "aws_cloudwatch_metric_alarm" "anomaly_detection" {
  for_each = var.enable_anomaly_detection ? toset(var.anomaly_detection_metrics) : []

  alarm_name          = "${local.name_prefix}-anomaly-${each.value}"
  comparison_operator = "LessThanLowerOrGreaterThanUpperThreshold"
  evaluation_periods  = "2"
  threshold_metric_id = "e1"
  alarm_description   = "Anomaly detected in metric ${each.value}"
  alarm_actions       = var.create_sns_topic ? [aws_sns_topic.alarms[0].arn] : []
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "e1"
    expression  = "ANOMALY_DETECTION_BAND(m1, 2)"
    label       = "Expected Range"
    return_data = true
  }

  metric_query {
    id = "m1"
    metric {
      metric_name = each.value
      namespace   = var.anomaly_detection_namespace
      period      = "300"
      stat        = "Average"
    }
  }

  tags = var.tags
}
