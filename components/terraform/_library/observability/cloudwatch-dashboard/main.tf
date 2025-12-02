##############################################
# CloudWatch Dashboard
##############################################

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.name_prefix}-dashboard"

  dashboard_body = jsonencode({
    widgets = concat(
      var.create_infrastructure_widgets ? local.infrastructure_widgets : [],
      var.create_application_widgets ? local.application_widgets : [],
      var.create_cost_widgets ? local.cost_widgets : [],
      var.create_security_widgets ? local.security_widgets : [],
      var.custom_widgets
    )
  })
}

##############################################
# Auto-Discovery Resources
##############################################

data "aws_instances" "discovered" {
  count = var.enable_auto_discovery ? 1 : 0

  instance_tags = var.discovery_tags

  filter {
    name   = "instance-state-name"
    values = ["running"]
  }
}

data "aws_lb" "discovered" {
  count = var.enable_auto_discovery && length(var.discovery_alb_names) > 0 ? length(var.discovery_alb_names) : 0
  name  = var.discovery_alb_names[count.index]
}

data "aws_rds_cluster" "discovered" {
  count              = var.enable_auto_discovery && length(var.discovery_rds_clusters) > 0 ? length(var.discovery_rds_clusters) : 0
  cluster_identifier = var.discovery_rds_clusters[count.index]
}

##############################################
# Widget Templates
##############################################

locals {
  # Infrastructure widgets
  infrastructure_widgets = [
    {
      type = "metric"
      properties = {
        metrics = [
          ["AWS/EC2", "CPUUtilization", { stat = "Average", period = 300 }]
        ]
        region = var.region
        title  = "EC2 CPU Utilization"
        period = 300
        yAxis = {
          left = {
            min = 0
            max = 100
          }
        }
      }
    },
    {
      type = "metric"
      properties = {
        metrics = [
          ["AWS/RDS", "CPUUtilization", { stat = "Average" }],
          [".", "DatabaseConnections", { stat = "Sum" }]
        ]
        region = var.region
        title  = "RDS Metrics"
        period = 300
      }
    },
    {
      type = "metric"
      properties = {
        metrics = [
          ["AWS/ELB", "RequestCount", { stat = "Sum" }],
          [".", "TargetResponseTime", { stat = "Average" }]
        ]
        region = var.region
        title  = "Load Balancer Metrics"
        period = 300
      }
    }
  ]

  # Application widgets
  application_widgets = [
    {
      type = "metric"
      properties = {
        metrics = [
          ["AWS/Lambda", "Invocations", { stat = "Sum" }],
          [".", "Errors", { stat = "Sum" }],
          [".", "Duration", { stat = "Average" }]
        ]
        region = var.region
        title  = "Lambda Functions"
        period = 300
      }
    },
    {
      type = "metric"
      properties = {
        metrics = [
          ["AWS/ApiGateway", "Count", { stat = "Sum" }],
          [".", "4XXError", { stat = "Sum" }],
          [".", "5XXError", { stat = "Sum" }],
          [".", "Latency", { stat = "Average" }]
        ]
        region = var.region
        title  = "API Gateway"
        period = 300
      }
    },
    {
      type = "log"
      properties = {
        query   = "SOURCE '/aws/lambda/*' | fields @timestamp, @message | sort @timestamp desc | limit 20"
        region  = var.region
        title   = "Recent Lambda Logs"
        stacked = false
      }
    }
  ]

  # Cost widgets
  cost_widgets = [
    {
      type = "metric"
      properties = {
        metrics = [
          ["AWS/Billing", "EstimatedCharges", "Currency", "USD", { stat = "Maximum" }]
        ]
        region = "us-east-1"
        title  = "Estimated Monthly Charges"
        period = 21600
      }
    },
    {
      type = "metric"
      properties = {
        metrics = [
          ["AWS/Usage", "ResourceCount", "Service", "EC2", "Type", "Resource", "Resource", "vCPU", { stat = "Average" }]
        ]
        region = var.region
        title  = "Resource Usage"
        period = 3600
      }
    }
  ]

  # Security widgets
  security_widgets = [
    {
      type = "metric"
      properties = {
        metrics = [
          ["AWS/WAF", "BlockedRequests", { stat = "Sum" }],
          [".", "AllowedRequests", { stat = "Sum" }]
        ]
        region = var.region
        title  = "WAF Metrics"
        period = 300
      }
    },
    {
      type = "log"
      properties = {
        query   = "fields @timestamp, eventName, userIdentity.principalId | filter eventName like /Delete/ or eventName like /Terminate/ | sort @timestamp desc | limit 20"
        region  = var.region
        title   = "Security Events"
        stacked = false
      }
    }
  ]
}

##############################################
# Cost Estimation Metric
##############################################

resource "aws_cloudwatch_log_metric_filter" "cost_estimation" {
  count = var.enable_cost_tracking ? 1 : 0

  name           = "${var.name_prefix}-cost-tracking"
  pattern        = "[time, request_id, event_type, cost]"
  log_group_name = var.cost_tracking_log_group

  metric_transformation {
    name      = "EstimatedCost"
    namespace = var.custom_namespace
    value     = "$cost"
    unit      = "None"
  }
}

##############################################
# Data Sources
##############################################

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
