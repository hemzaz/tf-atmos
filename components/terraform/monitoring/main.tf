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

  dashboard_name = "${var.tags["Environment"]}-infrastructure-overview"
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

# Certificate Monitoring Resources
locals {
  name_prefix = "${var.tags["Environment"]}-${var.tags["Name"] != null ? var.tags["Name"] : "monitoring"}"

  # Process certificate ARNs for dashboard
  certificate_arns         = var.certificate_arns
  certificate_names        = var.certificate_names
  certificate_domains      = var.certificate_domains
  certificate_statuses     = var.certificate_statuses
  certificate_expiry_dates = var.certificate_expiry_dates

  # Default values if not provided
  default_cert_arns         = length(local.certificate_arns) > 0 ? local.certificate_arns : ["placeholder"]
  default_cert_names        = length(local.certificate_names) > 0 ? local.certificate_names : ["No certificates found"]
  default_cert_domains      = length(local.certificate_domains) > 0 ? local.certificate_domains : ["example.com"]
  default_cert_statuses     = length(local.certificate_statuses) > 0 ? local.certificate_statuses : ["UNKNOWN"]
  default_cert_expiry_dates = length(local.certificate_expiry_dates) > 0 ? local.certificate_expiry_dates : ["Not available"]
}

# Certificate monitoring dashboard
resource "aws_cloudwatch_dashboard" "certificates" {
  count = var.enable_certificate_monitoring ? 1 : 0

  dashboard_name = "${local.name_prefix}-certificates"
  dashboard_body = templatefile(
    "${path.module}/templates/certificate-dashboard.json.tpl",
    {
      region            = var.region
      cluster_name      = var.eks_cluster_name
      cert_arns         = local.default_cert_arns
      cert_names        = local.default_cert_names
      cert_domains      = local.default_cert_domains
      cert_statuses     = local.default_cert_statuses
      cert_expiry_dates = local.default_cert_expiry_dates
      cert_alarm_arns   = var.certificate_alarm_arns
    }
  )
}

# Certificate expiry alarms
resource "aws_cloudwatch_metric_alarm" "certificate_expiry" {
  for_each = var.enable_certificate_monitoring ? {
    for i, arn in local.certificate_arns : local.certificate_names[i] => {
      arn  = arn
      name = local.certificate_names[i]
    }
    if i < length(local.certificate_names)
  } : {}

  alarm_name          = "${local.name_prefix}-cert-expiry-${each.key}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "DaysToExpiry"
  namespace           = "AWS/CertificateManager"
  period              = 86400 # 1 day
  statistic           = "Minimum"
  threshold           = var.certificate_expiry_threshold
  alarm_description   = "Certificate ${each.key} is approaching expiry"
  alarm_actions       = var.create_sns_topic ? [aws_sns_topic.alarms[0].arn] : []
  ok_actions          = var.create_sns_topic ? [aws_sns_topic.alarms[0].arn] : []

  dimensions = {
    CertificateArn = each.value.arn
  }

  tags = merge(
    var.tags,
    {
      Name = "${local.name_prefix}-cert-expiry-${each.key}"
    }
  )
}

# Backend Services Monitoring Dashboard
resource "aws_cloudwatch_dashboard" "backend_services" {
  count = var.enable_backend_monitoring ? 1 : 0

  dashboard_name = "${local.name_prefix}-backend-services"
  dashboard_body = templatefile(
    "${path.module}/templates/backend-dashboard.json.tpl",
    {
      region            = var.region
      environment       = var.tags["Environment"]
      cluster_name      = var.eks_cluster_name
      api_gateway_name  = var.api_gateway_name
      lambda_functions  = var.lambda_functions
      rds_instances     = var.rds_instances
      elasticache_clusters = var.elasticache_clusters
      load_balancers    = var.load_balancers
    }
  )
}

# API Gateway Performance Alarms
resource "aws_cloudwatch_metric_alarm" "api_gateway_latency" {
  for_each = var.enable_backend_monitoring && length(var.api_gateway_stages) > 0 ? toset(var.api_gateway_stages) : []

  alarm_name          = "${local.name_prefix}-api-gateway-${each.value}-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Latency"
  namespace           = "AWS/ApiGateway"
  period              = "300"
  statistic           = "Average"
  threshold           = var.api_gateway_latency_threshold
  alarm_description   = "API Gateway ${each.value} latency is too high"
  alarm_actions       = var.create_sns_topic ? [aws_sns_topic.alarms[0].arn] : []

  dimensions = {
    ApiName   = var.api_gateway_name
    Stage     = each.value
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "api_gateway_error_rate" {
  for_each = var.enable_backend_monitoring && length(var.api_gateway_stages) > 0 ? toset(var.api_gateway_stages) : []

  alarm_name          = "${local.name_prefix}-api-gateway-${each.value}-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "5XXError"
  namespace           = "AWS/ApiGateway"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.api_gateway_error_threshold
  alarm_description   = "API Gateway ${each.value} error rate is too high"
  alarm_actions       = var.create_sns_topic ? [aws_sns_topic.alarms[0].arn] : []

  dimensions = {
    ApiName   = var.api_gateway_name
    Stage     = each.value
  }

  tags = var.tags
}

# EKS Cluster Monitoring
resource "aws_cloudwatch_metric_alarm" "eks_cluster_failed_requests" {
  count = var.enable_backend_monitoring && var.eks_cluster_name != null ? 1 : 0

  alarm_name          = "${local.name_prefix}-eks-cluster-failed-requests"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "cluster_failed_request_count"
  namespace           = "ContainerInsights"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.eks_failed_requests_threshold
  alarm_description   = "EKS cluster ${var.eks_cluster_name} has high failed request count"
  alarm_actions       = var.create_sns_topic ? [aws_sns_topic.alarms[0].arn] : []

  dimensions = {
    ClusterName = var.eks_cluster_name
  }

  tags = var.tags
}

# Container Insights for EKS
resource "aws_cloudwatch_metric_alarm" "eks_pod_cpu_utilization" {
  count = var.enable_backend_monitoring && var.eks_cluster_name != null ? 1 : 0

  alarm_name          = "${local.name_prefix}-eks-pod-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "pod_cpu_utilization"
  namespace           = "ContainerInsights"
  period              = "300"
  statistic           = "Average"
  threshold           = var.eks_pod_cpu_threshold
  alarm_description   = "EKS pods have high CPU utilization"
  alarm_actions       = var.create_sns_topic ? [aws_sns_topic.alarms[0].arn] : []

  dimensions = {
    ClusterName = var.eks_cluster_name
    Namespace   = var.backend_services_namespace
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "eks_pod_memory_utilization" {
  count = var.enable_backend_monitoring && var.eks_cluster_name != null ? 1 : 0

  alarm_name          = "${local.name_prefix}-eks-pod-memory-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "pod_memory_utilization"
  namespace           = "ContainerInsights"
  period              = "300"
  statistic           = "Average"
  threshold           = var.eks_pod_memory_threshold
  alarm_description   = "EKS pods have high memory utilization"
  alarm_actions       = var.create_sns_topic ? [aws_sns_topic.alarms[0].arn] : []

  dimensions = {
    ClusterName = var.eks_cluster_name
    Namespace   = var.backend_services_namespace
  }

  tags = var.tags
}

# Application Load Balancer Monitoring
resource "aws_cloudwatch_metric_alarm" "alb_response_time" {
  for_each = var.enable_backend_monitoring ? toset(var.load_balancers) : []

  alarm_name          = "${local.name_prefix}-alb-${each.value}-response-time"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = "300"
  statistic           = "Average"
  threshold           = var.alb_response_time_threshold
  alarm_description   = "ALB ${each.value} response time is too high"
  alarm_actions       = var.create_sns_topic ? [aws_sns_topic.alarms[0].arn] : []

  dimensions = {
    LoadBalancer = each.value
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_hosts" {
  for_each = var.enable_backend_monitoring ? toset(var.load_balancers) : []

  alarm_name          = "${local.name_prefix}-alb-${each.value}-unhealthy-hosts"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = "300"
  statistic           = "Average"
  threshold           = var.alb_unhealthy_hosts_threshold
  alarm_description   = "ALB ${each.value} has unhealthy hosts"
  alarm_actions       = var.create_sns_topic ? [aws_sns_topic.alarms[0].arn] : []

  dimensions = {
    LoadBalancer = each.value
  }

  tags = var.tags
}

# ElastiCache Monitoring
resource "aws_cloudwatch_metric_alarm" "elasticache_cpu" {
  for_each = var.enable_backend_monitoring ? toset(var.elasticache_clusters) : []

  alarm_name          = "${local.name_prefix}-elasticache-${each.value}-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ElastiCache"
  period              = "300"
  statistic           = "Average"
  threshold           = var.elasticache_cpu_threshold
  alarm_description   = "ElastiCache cluster ${each.value} CPU utilization is high"
  alarm_actions       = var.create_sns_topic ? [aws_sns_topic.alarms[0].arn] : []

  dimensions = {
    CacheClusterId = each.value
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "elasticache_memory" {
  for_each = var.enable_backend_monitoring ? toset(var.elasticache_clusters) : []

  alarm_name          = "${local.name_prefix}-elasticache-${each.value}-memory"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "FreeableMemory"
  namespace           = "AWS/ElastiCache"
  period              = "300"
  statistic           = "Average"
  threshold           = var.elasticache_memory_threshold
  alarm_description   = "ElastiCache cluster ${each.value} free memory is low"
  alarm_actions       = var.create_sns_topic ? [aws_sns_topic.alarms[0].arn] : []

  dimensions = {
    CacheClusterId = each.value
  }

  tags = var.tags
}

# Synthetic Monitoring
resource "aws_synthetics_canary" "api_health_check" {
  count = var.enable_synthetic_monitoring ? 1 : 0

  name                 = "${local.name_prefix}-api-health-check"
  artifact_s3_location = "s3://${var.synthetics_bucket}/canary-artifacts"
  execution_role_arn   = aws_iam_role.synthetics_execution[0].arn
  handler              = "apiCanaryBlueprint.handler"
  zip_file             = "apicanary.zip"
  runtime_version      = "syn-nodejs-puppeteer-6.2"

  schedule {
    expression                = var.synthetics_schedule
    duration_in_seconds       = 0
  }

  run_config {
    timeout_in_seconds    = 60
    memory_in_mb         = 960
    active_tracing       = var.enable_tracing
    environment_variables = {
      API_ENDPOINT = var.api_endpoint
    }
  }

  success_retention_period = 31
  failure_retention_period = 31

  tags = var.tags
}

# IAM role for Synthetics canary
resource "aws_iam_role" "synthetics_execution" {
  count = var.enable_synthetic_monitoring ? 1 : 0

  name = "${local.name_prefix}-synthetics-execution-role"

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

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "synthetics_execution" {
  count = var.enable_synthetic_monitoring ? 1 : 0

  role       = aws_iam_role.synthetics_execution[0].name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchSyntheticsExecutionRolePolicy"
}

# X-Ray tracing (if enabled)
resource "aws_xray_sampling_rule" "backend_services" {
  count = var.enable_tracing ? 1 : 0

  rule_name      = "${local.name_prefix}-backend-services"
  priority       = 9000
  version        = 1
  reservoir_size = 1
  fixed_rate     = 0.1
  url_path       = "*"
  host           = "*"
  http_method    = "*"
  service_type   = "*"
  service_name   = "*"
  resource_arn   = "*"

  tags = var.tags
}

# Custom metrics for business KPIs
resource "aws_cloudwatch_log_metric_filter" "business_metrics" {
  for_each = var.business_metric_filters

  name           = "${local.name_prefix}-${each.key}"
  log_group_name = each.value.log_group_name
  pattern        = each.value.pattern

  metric_transformation {
    name      = "${local.name_prefix}_${each.key}"
    namespace = "BusinessMetrics/${var.tags["Environment"]}"
    value     = each.value.value
  }
}

resource "aws_cloudwatch_metric_alarm" "business_metrics" {
  for_each = var.business_metric_alarms

  alarm_name          = "${local.name_prefix}-business-${each.key}"
  comparison_operator = each.value.comparison_operator
  evaluation_periods  = each.value.evaluation_periods
  metric_name         = "${local.name_prefix}_${each.key}"
  namespace           = "BusinessMetrics/${var.tags["Environment"]}"
  period              = each.value.period
  statistic           = each.value.statistic
  threshold           = each.value.threshold
  alarm_description   = "Business metric ${each.key}: ${each.value.description}"
  alarm_actions       = var.create_sns_topic ? [aws_sns_topic.alarms[0].arn] : []

  tags = var.tags
}

