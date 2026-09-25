# CloudWatch Dashboards. infrastructure/performance/application are built
# with jsonencode from real per-resource dimensions (the same pattern as
# local.certificate_dashboard_body in main.tf, #166): a widget is emitted
# only when its backing list is non-empty, so the JSON never renders an
# always-empty "metrics": [] panel and never averages a metric over the
# whole account. security/cost stay on templatefile: every metric they plot
# (CloudTrailMetrics, GuardDuty, SecurityHub, AWS/Billing) is inherently
# account/region-wide, with no per-resource list in this component's inputs
# to dimension it by.
locals {
  # var.load_balancers accepts either the short "app/<name>/<id>" dimension
  # value or a full ELB ARN; the LoadBalancer dimension always wants the
  # former. Computed once and shared by every widget spec below.
  load_balancer_ids = [
    for lb in var.load_balancers :
    length(split("loadbalancer/", lb)) > 1 ? element(split("loadbalancer/", lb), 1) : lb
  ]

  # apigateway's api_name/rest_api_stage_name outputs are null for an HTTP
  # API (api_type = "HTTP"); a stack that reads one of those into
  # api_gateway_stages via `!terraform.state ... | [.]` would otherwise pass
  # a literal [null] here. compact() drops it so `toset(...)` in the
  # for_each alarms (main.tf, alarms.tf) never sees a null - "for_each" sets
  # must not contain null values.
  api_gateway_stages = compact(var.api_gateway_stages)

  dashboard_specs = {
    infrastructure = {
      heading = "infrastructure overview"
      widgets = [
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
          title   = "Load Balancer Requests"
          metrics = [for lb in local.load_balancer_ids : ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", lb]]
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
            for stage in local.api_gateway_stages : ["AWS/ApiGateway", "Count", "ApiName", var.api_gateway_name, "Stage", stage]
          ] : []
        },
      ]
    }

    performance = {
      heading = "performance metrics"
      widgets = [
        {
          # concat, not flatten: flatten removes every level of nesting, so
          # a list of [namespace, metric, dim_name, dim_value] rows would
          # collapse into one flat list of scalars instead of staying a list
          # of metric rows.
          title = "RDS Read/Write Latency"
          metrics = concat(
            [for db in var.rds_instances : ["AWS/RDS", "ReadLatency", "DBInstanceIdentifier", db]],
            [for db in var.rds_instances : ["AWS/RDS", "WriteLatency", "DBInstanceIdentifier", db]],
          )
        },
        {
          title   = "Lambda Duration (p99)"
          metrics = [for fn in var.lambda_functions : ["AWS/Lambda", "Duration", "FunctionName", fn, { stat = "p99" }]]
        },
        {
          title   = "ECS CPU Utilization"
          metrics = [for c in var.ecs_clusters : ["AWS/ECS", "CPUUtilization", "ClusterName", c]]
        },
        {
          title   = "ALB Target Response Time"
          metrics = [for lb in local.load_balancer_ids : ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", lb]]
        },
        {
          title   = "ElastiCache Freeable Memory"
          metrics = [for c in var.elasticache_clusters : ["AWS/ElastiCache", "FreeableMemory", "CacheClusterId", c]]
        },
        {
          title   = "EKS Pod CPU Utilization"
          metrics = var.eks_cluster_name != "" ? [["ContainerInsights", "pod_cpu_utilization", "ClusterName", var.eks_cluster_name]] : []
        },
        {
          title = "API Gateway Latency"
          metrics = var.api_gateway_name != "" ? [
            for stage in local.api_gateway_stages : ["AWS/ApiGateway", "Latency", "ApiName", var.api_gateway_name, "Stage", stage]
          ] : []
        },
      ]
    }

    application = {
      heading = "application metrics"
      widgets = [
        {
          title = "API Gateway Requests & 5XX Errors"
          metrics = var.api_gateway_name != "" ? concat(
            [for stage in local.api_gateway_stages : ["AWS/ApiGateway", "Count", "ApiName", var.api_gateway_name, "Stage", stage]],
            [for stage in local.api_gateway_stages : ["AWS/ApiGateway", "5XXError", "ApiName", var.api_gateway_name, "Stage", stage]],
          ) : []
        },
        {
          title   = "Lambda Errors"
          metrics = [for fn in var.lambda_functions : ["AWS/Lambda", "Errors", "FunctionName", fn]]
        },
        {
          title   = "Lambda Duration (Average)"
          metrics = [for fn in var.lambda_functions : ["AWS/Lambda", "Duration", "FunctionName", fn]]
        },
        {
          title   = "RDS Database Connections"
          metrics = [for db in var.rds_instances : ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", db]]
        },
        {
          title   = "ElastiCache Cache Hits"
          metrics = [for c in var.elasticache_clusters : ["AWS/ElastiCache", "CacheHits", "CacheClusterId", c]]
        },
        {
          title   = "ALB Target 5XX Errors"
          metrics = [for lb in local.load_balancer_ids : ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", lb]]
        },
      ]
    }

    # aws_cloudwatch_dashboard.backend_services (main.tf, enable_backend_monitoring).
    # Replaces templates/backend-dashboard.json.tpl (removed): that template
    # hardcoded ApiName/ClusterName to var.api_gateway_name/var.eks_cluster_name
    # with no "" guard, and its Lambda/RDS/ALB/ElastiCache widgets rendered an
    # empty metrics list on every real stack because none of them wired
    # lambda_functions/rds_instances/load_balancers/elasticache_clusters into
    # this component.
    backend = {
      heading = "backend services"
      widgets = [
        {
          title = "API Gateway Requests, Latency & Errors"
          metrics = var.api_gateway_name != "" ? concat(
            [for stage in local.api_gateway_stages : ["AWS/ApiGateway", "Count", "ApiName", var.api_gateway_name, "Stage", stage]],
            [for stage in local.api_gateway_stages : ["AWS/ApiGateway", "Latency", "ApiName", var.api_gateway_name, "Stage", stage]],
            [for stage in local.api_gateway_stages : ["AWS/ApiGateway", "4XXError", "ApiName", var.api_gateway_name, "Stage", stage]],
            [for stage in local.api_gateway_stages : ["AWS/ApiGateway", "5XXError", "ApiName", var.api_gateway_name, "Stage", stage]],
          ) : []
        },
        {
          title = "Lambda Duration, Errors & Throttles"
          metrics = concat(
            [for fn in var.lambda_functions : ["AWS/Lambda", "Duration", "FunctionName", fn]],
            [for fn in var.lambda_functions : ["AWS/Lambda", "Errors", "FunctionName", fn]],
            [for fn in var.lambda_functions : ["AWS/Lambda", "Throttles", "FunctionName", fn]],
          )
        },
        {
          title = "RDS CPU, Connections & Latency"
          metrics = concat(
            [for db in var.rds_instances : ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", db]],
            [for db in var.rds_instances : ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", db]],
            [for db in var.rds_instances : ["AWS/RDS", "ReadLatency", "DBInstanceIdentifier", db]],
            [for db in var.rds_instances : ["AWS/RDS", "WriteLatency", "DBInstanceIdentifier", db]],
          )
        },
        {
          title = "EKS Backend Services (Container Insights)"
          metrics = var.eks_cluster_name != "" ? [
            ["ContainerInsights", "pod_cpu_utilization", "ClusterName", var.eks_cluster_name, "Namespace", var.backend_services_namespace],
            ["ContainerInsights", "pod_memory_utilization", "ClusterName", var.eks_cluster_name, "Namespace", var.backend_services_namespace],
            ["ContainerInsights", "pod_network_rx_bytes", "ClusterName", var.eks_cluster_name, "Namespace", var.backend_services_namespace],
            ["ContainerInsights", "pod_network_tx_bytes", "ClusterName", var.eks_cluster_name, "Namespace", var.backend_services_namespace],
          ] : []
        },
        {
          title = "Application Load Balancers"
          metrics = concat(
            [for lb in local.load_balancer_ids : ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", lb]],
            [for lb in local.load_balancer_ids : ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", lb]],
            [for lb in local.load_balancer_ids : ["AWS/ApplicationELB", "HTTPCode_Target_4XX_Count", "LoadBalancer", lb]],
            [for lb in local.load_balancer_ids : ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", lb]],
          )
        },
        {
          title = "ElastiCache Performance"
          metrics = concat(
            [for c in var.elasticache_clusters : ["AWS/ElastiCache", "CPUUtilization", "CacheClusterId", c]],
            [for c in var.elasticache_clusters : ["AWS/ElastiCache", "FreeableMemory", "CacheClusterId", c]],
            [for c in var.elasticache_clusters : ["AWS/ElastiCache", "CurrConnections", "CacheClusterId", c]],
            [for c in var.elasticache_clusters : ["AWS/ElastiCache", "Evictions", "CacheClusterId", c]],
          )
        },
        {
          # BusinessMetrics/<Environment> namespace and <name_prefix>_<key>
          # metric name match what aws_cloudwatch_log_metric_filter.business_metrics
          # (main.tf) actually emits - not the fixed user_registrations/
          # api_calls_per_minute/active_users/error_rate names the removed
          # template hardcoded, which never matched any real metric.
          title   = "Business Metrics"
          metrics = [for k in keys(var.business_metric_filters) : ["BusinessMetrics/${var.tags["Environment"]}", "${local.name_prefix}_${k}"]]
        },
      ]
    }
  }

  # Widgets whose resource list is empty are dropped rather than rendered;
  # remaining widgets are laid out two per row under a text header.
  dashboard_bodies = {
    for key, spec in local.dashboard_specs : key => jsonencode({
      widgets = concat([
        {
          type   = "text"
          x      = 0
          y      = 0
          width  = 24
          height = 1
          properties = {
            markdown = "# ${var.tags["Environment"]} ${var.name} ${spec.heading}"
          }
        }
        ], [
        for idx, w in [for w in spec.widgets : w if length(w.metrics) > 0] : {
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

  # Only the fields security/cost still consume from templatefile(). environment
  # (var.environment, the lifecycle tier - dev/staging/prod) is deliberately
  # not var.tags["Environment"] (the stack instance name, e.g. testenv-01):
  # cost-dashboard.json.tpl's only use of it is a Logs Insights SOURCE path
  # (/aws/lambda/${environment}), a distinct, functional value, not a
  # cosmetic title - unlike the infrastructure/performance/application
  # dashboards' markdown headers (now jsonencode locals below), which do use
  # var.tags["Environment"] to match main.tf's certificate/backend dashboards.
  dashboard_vars = {
    region      = var.region
    environment = var.environment
  }
}

# Infrastructure Overview Dashboard. create_dashboard is a legacy alias of
# create_infrastructure_dashboard (see variables.tf): both used to drive
# separate Terraform resources managing the same dashboard content under two
# different names ("-overview" vs "-infrastructure-overview"); every real
# stack instance set create_dashboard: true, so every instance created both.
# There is now a single resource, and either flag creates it.
resource "aws_cloudwatch_dashboard" "infrastructure" {
  count = var.create_dashboard || var.create_infrastructure_dashboard ? 1 : 0

  dashboard_name = "${local.name_prefix}-infrastructure-overview"
  dashboard_body = local.dashboard_bodies["infrastructure"]
}

# Security Dashboard
resource "aws_cloudwatch_dashboard" "security" {
  count = var.create_security_dashboard ? 1 : 0

  dashboard_name = "${local.name_prefix}-security-monitoring"

  dashboard_body = templatefile(
    "${path.module}/templates/security-dashboard.json.tpl",
    local.dashboard_vars
  )
}

# Cost Optimization Dashboard
resource "aws_cloudwatch_dashboard" "cost" {
  count = var.create_cost_dashboard ? 1 : 0

  dashboard_name = "${local.name_prefix}-cost-optimization"

  dashboard_body = templatefile(
    "${path.module}/templates/cost-dashboard.json.tpl",
    local.dashboard_vars
  )
}

# Performance Dashboard
resource "aws_cloudwatch_dashboard" "performance" {
  count = var.create_performance_dashboard ? 1 : 0

  dashboard_name = "${local.name_prefix}-performance-metrics"
  dashboard_body = local.dashboard_bodies["performance"]
}

# Application Dashboard
resource "aws_cloudwatch_dashboard" "application" {
  count = var.create_application_dashboard ? 1 : 0

  dashboard_name = "${local.name_prefix}-application-metrics"
  dashboard_body = local.dashboard_bodies["application"]
}

# Certificate Monitoring Dashboard: owned solely by
# aws_cloudwatch_dashboard.certificate_monitoring in main.tf
# (enable_certificate_monitoring || create_certificate_dashboard). This used
# to be a second Terraform resource naming a different dashboard
# ("${local.name_prefix}-certificate-monitoring") from the exact same
# local.certificate_dashboard_body; create_certificate_dashboard now creates
# the one certificate_monitoring resource instead. See variables.tf/main.tf.

# Custom Dashboard (user-provided JSON)
resource "aws_cloudwatch_dashboard" "custom" {
  for_each = var.custom_dashboards

  dashboard_name = "${local.name_prefix}-${each.key}"
  dashboard_body = each.value.body
}

# Backend Services Dashboard: owned solely by aws_cloudwatch_dashboard.backend_services
# in main.tf (enable_backend_monitoring). This used to be a second Terraform
# resource naming the exact same dashboard ("${local.name_prefix}-backend-services"),
# so enabling both create_backend_dashboard and enable_backend_monitoring made
# two resources manage one CloudWatch object; each apply overwrote the other's
# state. create_backend_dashboard has been removed - see variables.tf.

# Dashboard URLs output
output "dashboard_urls" {
  description = "URLs to access CloudWatch Dashboards"
  value = {
    infrastructure = var.create_dashboard || var.create_infrastructure_dashboard ? "https://console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${aws_cloudwatch_dashboard.infrastructure[0].dashboard_name}" : null
    security       = var.create_security_dashboard ? "https://console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${aws_cloudwatch_dashboard.security[0].dashboard_name}" : null
    cost           = var.create_cost_dashboard ? "https://console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${aws_cloudwatch_dashboard.cost[0].dashboard_name}" : null
    performance    = var.create_performance_dashboard ? "https://console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${aws_cloudwatch_dashboard.performance[0].dashboard_name}" : null
    application    = var.create_application_dashboard ? "https://console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${aws_cloudwatch_dashboard.application[0].dashboard_name}" : null
    backend        = var.enable_backend_monitoring ? "https://console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${aws_cloudwatch_dashboard.backend_services[0].dashboard_name}" : null
    certificates   = var.enable_certificate_monitoring || var.create_certificate_dashboard ? "https://console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${aws_cloudwatch_dashboard.certificate_monitoring[0].dashboard_name}" : null
  }
}

# Dashboard names
output "dashboard_names" {
  description = "Names of created CloudWatch Dashboards"
  value = {
    infrastructure = var.create_dashboard || var.create_infrastructure_dashboard ? aws_cloudwatch_dashboard.infrastructure[0].dashboard_name : null
    security       = var.create_security_dashboard ? aws_cloudwatch_dashboard.security[0].dashboard_name : null
    cost           = var.create_cost_dashboard ? aws_cloudwatch_dashboard.cost[0].dashboard_name : null
    performance    = var.create_performance_dashboard ? aws_cloudwatch_dashboard.performance[0].dashboard_name : null
    application    = var.create_application_dashboard ? aws_cloudwatch_dashboard.application[0].dashboard_name : null
    backend        = var.enable_backend_monitoring ? aws_cloudwatch_dashboard.backend_services[0].dashboard_name : null
    certificates   = var.enable_certificate_monitoring || var.create_certificate_dashboard ? aws_cloudwatch_dashboard.certificate_monitoring[0].dashboard_name : null
    custom         = { for k, v in aws_cloudwatch_dashboard.custom : k => v.dashboard_name }
  }
}
