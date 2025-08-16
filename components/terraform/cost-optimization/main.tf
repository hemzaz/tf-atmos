# Cost Optimization Module - Automated Infrastructure Cost Management
# This module implements automated cost optimization strategies across all environments

terraform {
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

locals {
  name_prefix = "${var.namespace}-${var.environment}-${var.stage}"

  # Cost optimization settings per environment
  optimization_settings = {
    dev = {
      auto_shutdown   = true
      use_spot        = true
      spot_percentage = 70
      schedule_on     = "0 7 * * MON-FRI"
      schedule_off    = "0 19 * * MON-FRI"
      enable_ri       = false
      enable_sp       = false
    }
    staging = {
      auto_shutdown   = true
      use_spot        = true
      spot_percentage = 50
      schedule_on     = "0 6 * * MON-FRI"
      schedule_off    = "0 20 * * MON-FRI"
      enable_ri       = false
      enable_sp       = true
    }
    prod = {
      auto_shutdown   = false
      use_spot        = true
      spot_percentage = 20
      schedule_on     = null
      schedule_off    = null
      enable_ri       = true
      enable_sp       = true
    }
  }

  current_settings = lookup(local.optimization_settings, var.environment, local.optimization_settings.dev)

  common_tags = merge(
    var.tags,
    {
      Namespace   = var.namespace
      Environment = var.environment
      Stage       = var.stage
      CostCenter  = var.cost_center
      ManagedBy   = "Terraform"
      Module      = "cost-optimization"
    }
  )
}

# ========================================
# Instance Scheduler for Auto Start/Stop
# ========================================

resource "aws_iam_role" "scheduler" {
  count = local.current_settings.auto_shutdown ? 1 : 0

  name = "${local.name_prefix}-instance-scheduler-role"

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

  tags = local.common_tags
}

resource "aws_iam_role_policy" "scheduler" {
  count = local.current_settings.auto_shutdown ? 1 : 0

  name = "${local.name_prefix}-instance-scheduler-policy"
  role = aws_iam_role.scheduler[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:StopInstances",
          "ec2:StartInstances",
          "ec2:DescribeTags",
          "rds:DescribeDBInstances",
          "rds:StopDBInstance",
          "rds:StartDBInstance",
          "rds:ListTagsForResource",
          "eks:DescribeNodegroup",
          "eks:UpdateNodegroupConfig",
          "autoscaling:UpdateAutoScalingGroup",
          "autoscaling:DescribeAutoScalingGroups"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Lambda function for instance scheduling
resource "aws_lambda_function" "scheduler" {
  count = local.current_settings.auto_shutdown ? 1 : 0

  function_name = "${local.name_prefix}-instance-scheduler"
  role          = aws_iam_role.scheduler[0].arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 60
  memory_size   = 256

  environment {
    variables = {
      ENVIRONMENT = var.environment
      ACTION      = "START_STOP"
      TAG_FILTERS = jsonencode({
        Environment  = var.environment
        AutoShutdown = "true"
      })
    }
  }

  filename         = data.archive_file.scheduler_lambda[0].output_path
  source_code_hash = data.archive_file.scheduler_lambda[0].output_base64sha256

  tags = local.common_tags
}

# Lambda deployment package
data "archive_file" "scheduler_lambda" {
  count = local.current_settings.auto_shutdown ? 1 : 0

  type        = "zip"
  output_path = "${path.module}/scheduler_lambda.zip"

  source {
    content  = file("${path.module}/lambda/scheduler.py")
    filename = "index.py"
  }
}

# CloudWatch Event Rules for scheduling
resource "aws_cloudwatch_event_rule" "start_instances" {
  count = local.current_settings.auto_shutdown && local.current_settings.schedule_on != null ? 1 : 0

  name                = "${local.name_prefix}-start-instances"
  description         = "Trigger instance start"
  schedule_expression = "cron(${local.current_settings.schedule_on})"

  tags = local.common_tags
}

resource "aws_cloudwatch_event_rule" "stop_instances" {
  count = local.current_settings.auto_shutdown && local.current_settings.schedule_off != null ? 1 : 0

  name                = "${local.name_prefix}-stop-instances"
  description         = "Trigger instance stop"
  schedule_expression = "cron(${local.current_settings.schedule_off})"

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "start_lambda" {
  count = local.current_settings.auto_shutdown && local.current_settings.schedule_on != null ? 1 : 0

  rule      = aws_cloudwatch_event_rule.start_instances[0].name
  target_id = "StartInstancesLambda"
  arn       = aws_lambda_function.scheduler[0].arn

  input = jsonencode({
    action = "START"
  })
}

resource "aws_cloudwatch_event_target" "stop_lambda" {
  count = local.current_settings.auto_shutdown && local.current_settings.schedule_off != null ? 1 : 0

  rule      = aws_cloudwatch_event_rule.stop_instances[0].name
  target_id = "StopInstancesLambda"
  arn       = aws_lambda_function.scheduler[0].arn

  input = jsonencode({
    action = "STOP"
  })
}

resource "aws_lambda_permission" "allow_cloudwatch_start" {
  count = local.current_settings.auto_shutdown && local.current_settings.schedule_on != null ? 1 : 0

  statement_id  = "AllowExecutionFromCloudWatchStart"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.scheduler[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.start_instances[0].arn
}

resource "aws_lambda_permission" "allow_cloudwatch_stop" {
  count = local.current_settings.auto_shutdown && local.current_settings.schedule_off != null ? 1 : 0

  statement_id  = "AllowExecutionFromCloudWatchStop"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.scheduler[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.stop_instances[0].arn
}

# ========================================
# Cost Anomaly Detection
# ========================================

resource "aws_ce_anomaly_monitor" "main" {
  name              = "${local.name_prefix}-cost-monitor"
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "SERVICE"

  tags = local.common_tags
}

resource "aws_ce_anomaly_subscription" "main" {
  name      = "${local.name_prefix}-cost-anomaly-subscription"
  frequency = "DAILY"

  monitor_arn_list = [
    aws_ce_anomaly_monitor.main.arn
  ]

  subscriber {
    type    = "EMAIL"
    address = var.cost_anomaly_notification_email
  }

  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_PERCENTAGE"
      values        = ["20"]
      match_options = ["GREATER_THAN_OR_EQUAL"]
    }
  }

  tags = local.common_tags
}

# ========================================
# Budget Alerts
# ========================================

resource "aws_budgets_budget" "monthly" {
  name         = "${local.name_prefix}-monthly-budget"
  budget_type  = "COST"
  limit_amount = var.monthly_budget_limit
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name = "TagKeyValue"
    values = [
      "Environment$${var.environment}"
    ]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.budget_notification_emails
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = var.budget_notification_emails
  }
}

# ========================================
# Savings Plans Recommendation Tracker
# ========================================

resource "aws_lambda_function" "savings_analyzer" {
  function_name = "${local.name_prefix}-savings-analyzer"
  role          = aws_iam_role.savings_analyzer.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 300
  memory_size   = 512

  environment {
    variables = {
      ENVIRONMENT = var.environment
      SNS_TOPIC   = aws_sns_topic.cost_alerts.arn
    }
  }

  filename         = data.archive_file.savings_analyzer_lambda.output_path
  source_code_hash = data.archive_file.savings_analyzer_lambda.output_base64sha256

  tags = local.common_tags
}

data "archive_file" "savings_analyzer_lambda" {
  type        = "zip"
  output_path = "${path.module}/savings_analyzer_lambda.zip"

  source {
    content  = file("${path.module}/lambda/savings_analyzer.py")
    filename = "index.py"
  }
}

resource "aws_iam_role" "savings_analyzer" {
  name = "${local.name_prefix}-savings-analyzer-role"

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

  tags = local.common_tags
}

resource "aws_iam_role_policy" "savings_analyzer" {
  name = "${local.name_prefix}-savings-analyzer-policy"
  role = aws_iam_role.savings_analyzer.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ce:GetSavingsPlansPurchaseRecommendation",
          "ce:GetReservationPurchaseRecommendation",
          "ce:GetRightsizingRecommendation",
          "ce:GetCostAndUsage",
          "ce:GetCostForecast",
          "compute-optimizer:GetEC2InstanceRecommendations",
          "compute-optimizer:GetAutoScalingGroupRecommendations",
          "compute-optimizer:GetEBSVolumeRecommendations"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.cost_alerts.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Schedule weekly savings analysis
resource "aws_cloudwatch_event_rule" "savings_analysis" {
  name                = "${local.name_prefix}-savings-analysis"
  description         = "Weekly savings plan analysis"
  schedule_expression = "cron(0 9 ? * MON *)"

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "savings_analyzer_lambda" {
  rule      = aws_cloudwatch_event_rule.savings_analysis.name
  target_id = "SavingsAnalyzerLambda"
  arn       = aws_lambda_function.savings_analyzer.arn
}

resource "aws_lambda_permission" "allow_cloudwatch_savings" {
  statement_id  = "AllowExecutionFromCloudWatchSavings"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.savings_analyzer.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.savings_analysis.arn
}

# ========================================
# SNS Topic for Cost Alerts
# ========================================

resource "aws_sns_topic" "cost_alerts" {
  name = "${local.name_prefix}-cost-alerts"

  tags = local.common_tags
}

resource "aws_sns_topic_subscription" "cost_alerts_email" {
  for_each = toset(var.cost_alert_emails)

  topic_arn = aws_sns_topic.cost_alerts.arn
  protocol  = "email"
  endpoint  = each.value
}

# ========================================
# Unused Resource Cleanup
# ========================================

resource "aws_lambda_function" "resource_cleanup" {
  function_name = "${local.name_prefix}-resource-cleanup"
  role          = aws_iam_role.resource_cleanup.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 300
  memory_size   = 512

  environment {
    variables = {
      ENVIRONMENT = var.environment
      DRY_RUN     = var.cleanup_dry_run
      SNS_TOPIC   = aws_sns_topic.cost_alerts.arn
    }
  }

  filename         = data.archive_file.cleanup_lambda.output_path
  source_code_hash = data.archive_file.cleanup_lambda.output_base64sha256

  tags = local.common_tags
}

data "archive_file" "cleanup_lambda" {
  type        = "zip"
  output_path = "${path.module}/cleanup_lambda.zip"

  source {
    content  = file("${path.module}/lambda/cleanup.py")
    filename = "index.py"
  }
}

resource "aws_iam_role" "resource_cleanup" {
  name = "${local.name_prefix}-resource-cleanup-role"

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

  tags = local.common_tags
}

resource "aws_iam_role_policy" "resource_cleanup" {
  name = "${local.name_prefix}-resource-cleanup-policy"
  role = aws_iam_role.resource_cleanup.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeVolumes",
          "ec2:DescribeSnapshots",
          "ec2:DescribeAddresses",
          "ec2:DeleteVolume",
          "ec2:DeleteSnapshot",
          "ec2:ReleaseAddress",
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DeleteLoadBalancer",
          "ec2:DescribeInstances",
          "ec2:TerminateInstances"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "ec2:ResourceTag/Environment" = var.environment
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.cost_alerts.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Schedule weekly cleanup
resource "aws_cloudwatch_event_rule" "cleanup" {
  name                = "${local.name_prefix}-resource-cleanup"
  description         = "Weekly unused resource cleanup"
  schedule_expression = "cron(0 2 ? * SUN *)"

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "cleanup_lambda" {
  rule      = aws_cloudwatch_event_rule.cleanup.name
  target_id = "CleanupLambda"
  arn       = aws_lambda_function.resource_cleanup.arn
}

resource "aws_lambda_permission" "allow_cloudwatch_cleanup" {
  statement_id  = "AllowExecutionFromCloudWatchCleanup"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.resource_cleanup.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.cleanup.arn
}

# ========================================
# CloudWatch Dashboard for Cost Monitoring
# ========================================

resource "aws_cloudwatch_dashboard" "cost_optimization" {
  dashboard_name = "${local.name_prefix}-cost-optimization"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/Billing", "EstimatedCharges", { stat = "Maximum", label = "Current Month Charges" }]
          ]
          period = 86400
          stat   = "Maximum"
          region = "us-east-1"
          title  = "Estimated Monthly Charges"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/EC2", "CPUUtilization", { stat = "Average", label = "Average CPU" }],
            [".", ".", { stat = "Maximum", label = "Max CPU" }]
          ]
          period = 300
          stat   = "Average"
          region = var.region
          title  = "EC2 CPU Utilization"
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/RDS", "CPUUtilization", { stat = "Average" }],
            [".", "DatabaseConnections", { stat = "Average", yAxis = "right" }]
          ]
          period = 300
          stat   = "Average"
          region = var.region
          title  = "RDS Utilization"
        }
      }
    ]
  })
}