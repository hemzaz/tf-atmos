resource "aws_cloudwatch_log_group" "main" {
  for_each = var.log_groups

  name              = "${local.name_prefix}/${each.key}"
  retention_in_days = each.value.retention_days
  kms_key_id        = var.kms_key_id

  tags = { Name = "${local.name_prefix}/${each.key}" }
}

locals {
  # Real per-resource dimensions instead of one metric averaged over the
  # whole account, built the same way local.certificate_dashboard_body is
  # below: a widget is emitted only when its backing list is non-empty, so
  # the JSON never renders an always-empty "metrics": [] panel (#166).
  #
  # load_balancers accepts either the short "app/<name>/<id>" dimension value
  # or a full ELB ARN; the LoadBalancer dimension always wants the former.
  overview_widget_specs = [
    {
      title   = "RDS CPU Utilization"
      metrics = [for db in var.rds_instances : ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", db]]
    },
    {
      title   = "ECS CPU Utilization"
      metrics = [for c in var.ecs_clusters : ["AWS/ECS", "CPUUtilization", "ClusterName", c]]
    },
    {
      title   = "Lambda Invocations"
      metrics = [for fn in var.lambda_functions : ["AWS/Lambda", "Invocations", "FunctionName", fn]]
    },
    {
      title = "Load Balancer Requests"
      metrics = [
        for lb in var.load_balancers : ["AWS/ApplicationELB", "RequestCount", "LoadBalancer",
          # The LoadBalancer dimension wants "app/<name>/<id>", not a full ARN
          # ("arn:...:loadbalancer/app/<name>/<id>"). Strip everything up to
          # and including "loadbalancer/" when a full ARN is given; a value
          # already in the short form passes through unchanged.
          length(split("loadbalancer/", lb)) > 1 ? element(split("loadbalancer/", lb), 1) : lb
        ]
      ]
    },
    {
      title   = "ElastiCache CPU Utilization"
      metrics = [for c in var.elasticache_clusters : ["AWS/ElastiCache", "CPUUtilization", "CacheClusterId", c]]
    },
    {
      title   = "EKS Node CPU Utilization"
      metrics = var.eks_cluster_name != "" ? [["ContainerInsights", "node_cpu_utilization", "ClusterName", var.eks_cluster_name]] : []
    },
    {
      title = "API Gateway Requests"
      metrics = var.api_gateway_name != "" ? [
        for stage in var.api_gateway_stages : ["AWS/ApiGateway", "Count", "ApiName", var.api_gateway_name, "Stage", stage]
      ] : []
    },
  ]

  # Widgets whose resource list is empty are dropped rather than rendered.
  overview_active_widgets = [for w in local.overview_widget_specs : w if length(w.metrics) > 0]

  overview_dashboard_body = jsonencode({
    widgets = concat([
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 1
        properties = {
          markdown = "# ${var.tags["Environment"]} ${var.name} overview"
        }
      }
      ], [
      for idx, w in local.overview_active_widgets : {
        type   = "metric"
        x      = (idx % 2) * 12
        y      = 1 + floor(idx / 2) * 6
        width  = 12
        height = 6
        properties = {
          metrics = w.metrics
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = w.title
          period  = 300
        }
      }
    ])
  })
}

# Named "-overview" (not "-infrastructure-overview") so it never collides
# with dashboards.tf's aws_cloudwatch_dashboard.infrastructure
# (create_infrastructure_dashboard), which owns that name; both default on,
# so before this rename enabling both flags produced two Terraform resources
# managing the exact same CloudWatch dashboard name.
resource "aws_cloudwatch_dashboard" "main" {
  count = var.create_dashboard ? 1 : 0

  dashboard_name = "${local.name_prefix}-overview"
  dashboard_body = local.overview_dashboard_body
}

resource "aws_sns_topic" "alarms" {
  count = var.create_sns_topic ? 1 : 0

  name              = "${local.name_prefix}-alarms"
  kms_master_key_id = var.kms_key_id

  tags = { Name = "${local.name_prefix}-alarms" }
}

resource "aws_sns_topic_subscription" "alarms_email" {
  count = var.create_sns_topic && length(var.alarm_email_subscriptions) > 0 ? length(var.alarm_email_subscriptions) : 0

  topic_arn = aws_sns_topic.alarms[0].arn
  protocol  = "email"
  endpoint  = var.alarm_email_subscriptions[count.index]
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  for_each = var.cpu_alarms

  alarm_name          = "${local.name_prefix}-${each.key}-high-cpu"
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

  tags = { Name = "${local.name_prefix}-${each.key}-high-cpu" }
}

resource "aws_cloudwatch_metric_alarm" "memory_high" {
  for_each = var.memory_alarms

  alarm_name          = "${local.name_prefix}-${each.key}-high-memory"
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

  tags = { Name = "${local.name_prefix}-${each.key}-high-memory" }
}

resource "aws_cloudwatch_metric_alarm" "db_connections_high" {
  for_each = var.db_connection_alarms

  alarm_name          = "${local.name_prefix}-${each.key}-high-connections"
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

  tags = { Name = "${local.name_prefix}-${each.key}-high-connections" }
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each = var.lambda_error_alarms

  alarm_name          = "${local.name_prefix}-${each.key}-errors"
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

  tags = { Name = "${local.name_prefix}-${each.key}-errors" }
}

# Create a CloudWatch Logs Metric Filter and Alarm for specific log patterns
resource "aws_cloudwatch_log_metric_filter" "error_logs" {
  for_each = var.log_metric_filters

  name           = "${local.name_prefix}-${each.key}-errors"
  pattern        = each.value.pattern
  log_group_name = aws_cloudwatch_log_group.main[each.value.log_group_name].name

  metric_transformation {
    name      = "${local.name_prefix}_${each.key}_errors"
    namespace = "CustomMetrics/${local.name_prefix}"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "log_errors" {
  for_each = var.log_metric_filters

  alarm_name          = "${local.name_prefix}-${each.key}-log-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = each.value.evaluation_periods
  metric_name         = "${local.name_prefix}_${each.key}_errors"
  namespace           = "CustomMetrics/${local.name_prefix}"
  period              = each.value.period
  statistic           = "Sum"
  threshold           = each.value.threshold
  alarm_description   = "Error logs detected for ${each.key}"
  alarm_actions       = var.create_sns_topic ? [aws_sns_topic.alarms[0].arn] : []

  tags = { Name = "${local.name_prefix}-${each.key}-log-errors" }
}

# Certificate Monitoring Resources
locals {
  # Cloud Posse null-label style id (terraform-null-label: id = ...-name):
  # every named resource in this component, not var.tags["Environment"]
  # alone. var.name defaults to "monitoring", but every real stack sets
  # distinct values ("main"/"data") on its two instances of this component so
  # their AWS resources never collide.
  name_prefix = "${var.tags["Environment"]}-${var.name}"

  # Process certificate ARNs for dashboard
  certificate_arns         = var.certificate_arns
  certificate_names        = var.certificate_names
  certificate_domains      = var.certificate_domains
  certificate_statuses     = var.certificate_statuses
  certificate_expiry_dates = var.certificate_expiry_dates

  # One row per ARN, indexing the raw lists. try() keeps a shorter
  # names/domains/... list from failing the plan (monitoring/data sets
  # certificate_arns alone) without borrowing another row's placeholder. The
  # placeholder row is used only when there are no ARNs at all.
  certificate_dashboard_rows = length(local.certificate_arns) > 0 ? [
    for i, arn in local.certificate_arns : {
      arn    = arn
      name   = try(local.certificate_names[i], arn)
      domain = try(local.certificate_domains[i], "unknown")
      status = try(local.certificate_statuses[i], "UNKNOWN")
      expiry = try(local.certificate_expiry_dates[i], "Not available")
    }
    ] : [{
      arn    = "placeholder"
      name   = "No certificates found"
      domain = "example.com"
      status = "UNKNOWN"
      expiry = "Not available"
  }]

  # The component's own expiry alarms plus any the stack passes in, merged the
  # way Cloud Posse merges alarm endpoints (terraform-aws-cloudtrail-cloudwatch-
  # alarms alarms.tf:7, distinct(compact(concat(...)))).
  certificate_dashboard_alarm_arns = distinct(compact(concat(
    var.certificate_alarm_arns,
    [for a in aws_cloudwatch_metric_alarm.certificate_expiry : a.arn],
  )))

  # Built with jsonencode, not templatefile. The template interpolated
  # join("\n\n", ...) inside a JSON string, and an HCL "\n" is a real newline,
  # so every render was invalid JSON ("invalid character '\n' in string
  # literal"). jsonencode escapes it. Shared by both certificate dashboards
  # (certificate_monitoring below, certificates in dashboards.tf).
  #
  # widgets is a concat() of lists, and a list is empty when its widget has
  # nothing valid to show. Cloud Posse likewise derives the widget list from
  # the data instead of emitting fixed widgets (terraform-aws-cloudtrail-
  # cloudwatch-alarms alarms.tf:81-101). An Alarm Status widget requires
  # 1-100 ARNs, so it is omitted when there are none. The log widget is
  # omitted without a cluster name, since it would query /aws/eks//...
  certificate_dashboard_body = jsonencode({
    widgets = concat([
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 1
        properties = {
          markdown = "# Certificate Management Dashboard\nMonitoring TLS certificates across AWS ACM and Kubernetes clusters"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 1
        width  = 12
        height = 6
        properties = {
          metrics = [
            for c in local.certificate_dashboard_rows :
            ["AWS/CertificateManager", "DaysToExpiry", "CertificateArn", c.arn, { label = c.name }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = "Certificate Days to Expiry"
          period  = 300
          stat    = "Average"
          yAxis   = { left = { min = 0, max = 90 } }
          annotations = {
            horizontal = [
              { label = "Critical", value = 14, color = "#d13212" },
              { label = "Warning", value = 30, color = "#ff7f0e" },
            ]
          }
        }
      },
      {
        type   = "text"
        x      = 12
        y      = 1
        width  = 12
        height = 6
        properties = {
          markdown = join("\n\n", concat(
            ["## Certificate Status"],
            [
              for c in local.certificate_dashboard_rows :
              "- **${c.name}**\n  - ARN: `${c.arn}`\n  - Domain: ${c.domain}\n  - Status: ${c.status}\n  - Expiry: ${c.expiry}"
            ],
            ["**Note:** Certificates should be renewed at least 30 days before expiry to avoid service disruption."],
          ))
        }
      },
      ], length(local.certificate_dashboard_alarm_arns) > 0 ? [
      {
        type   = "alarm"
        x      = 0
        y      = 7
        width  = 24
        height = 6
        properties = {
          title  = "Certificate Expiry Alarms"
          alarms = local.certificate_dashboard_alarm_arns
        }
      },
      ] : [], [
      {
        type   = "metric"
        x      = 0
        y      = 13
        width  = 24
        height = 6
        properties = {
          metrics = [
            ["AWS/SecretsManager", "ResourceCount", "Service", "Secrets Manager", "Type", "Resource", { stat = "Sum" }],
            ["AWS/SecretsManager", "SuccessfulRequestCount", "Service", "Secrets Manager", "Type", "API", { stat = "Sum" }],
            ["AWS/SecretsManager", "ErrorCount", "Service", "Secrets Manager", "Type", "Error", { stat = "Sum" }],
          ]
          region  = var.region
          title   = "Secrets Manager Activity (for Certificate Storage)"
          view    = "timeSeries"
          stacked = false
          period  = 300
        }
      },
      ], var.eks_cluster_name != "" ? [
      {
        type   = "log"
        x      = 0
        y      = 19
        width  = 24
        height = 6
        properties = {
          query  = "SOURCE '/aws/eks/${var.eks_cluster_name}/external-secrets' | fields @timestamp, @message\n| filter @message like /certificate/ or @message like /secret/\n| sort @timestamp desc\n| limit 100"
          region = var.region
          title  = "External Secrets Operator Logs (Certificate Related)"
          view   = "table"
        }
      },
    ] : [])
  })
}

# Certificate monitoring dashboard (renamed from "certificates", which collided with dashboards.tf)
resource "aws_cloudwatch_dashboard" "certificate_monitoring" {
  count = var.enable_certificate_monitoring ? 1 : 0

  dashboard_name = "${local.name_prefix}-certificates"
  dashboard_body = local.certificate_dashboard_body
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

  tags = { Name = "${local.name_prefix}-cert-expiry-${each.key}" }
}

# Backend Services Monitoring Dashboard
resource "aws_cloudwatch_dashboard" "backend_services" {
  count = var.enable_backend_monitoring ? 1 : 0

  dashboard_name = "${local.name_prefix}-backend-services"
  dashboard_body = templatefile(
    "${path.module}/templates/backend-dashboard.json.tpl",
    {
      region               = var.region
      environment          = var.tags["Environment"]
      cluster_name         = var.eks_cluster_name
      api_gateway_name     = var.api_gateway_name
      lambda_functions     = var.lambda_functions
      rds_instances        = var.rds_instances
      elasticache_clusters = var.elasticache_clusters
      load_balancers       = var.load_balancers
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
    ApiName = var.api_gateway_name
    Stage   = each.value
  }
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
    ApiName = var.api_gateway_name
    Stage   = each.value
  }
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
    expression          = var.synthetics_schedule
    duration_in_seconds = 0
  }

  run_config {
    timeout_in_seconds = 60
    memory_in_mb       = 960
    active_tracing     = var.enable_tracing
    environment_variables = {
      API_ENDPOINT = var.api_endpoint
    }
  }

  success_retention_period = 31
  failure_retention_period = 31
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
}

resource "aws_iam_role_policy_attachment" "synthetics_execution" {
  count = var.enable_synthetic_monitoring ? 1 : 0

  role       = aws_iam_role.synthetics_execution[0].name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchSyntheticsExecutionRolePolicy"
}

# X-Ray tracing (if enabled)
resource "aws_xray_sampling_rule" "backend_services" {
  count = var.enable_tracing ? 1 : 0

  # X-Ray caps rule names at 32 characters, so this is always truncated. It is
  # built from local.name_prefix (Environment-name), not Environment alone,
  # so main and data still get distinct rule names post-truncation for every
  # real stack's short environment names (testenv-01, staging, production).
  rule_name      = substr("${local.name_prefix}-backend-services", 0, 32)
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
}

