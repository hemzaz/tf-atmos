# Cost Optimization Module - Automated Infrastructure Cost Management
#
# No Cloud Posse component exists for this; each Lambda function is packaged
# the way Cloud Posse's aws-lambda component does it
# (https://github.com/cloudposse-terraform-components/aws-lambda): a local zip
# built by the archive provider with source_code_hash driving replacement,
# rather than a pre-built S3 artifact. IAM policies are built with
# jsonencode(), as in this repo's lambda and stepfunctions components, so
# every one of them is a plain value computable at plan time.
#
# Three scheduled Lambda functions:
#   - scheduler:        start/stop EC2, RDS and ASGs on a per-stage schedule.
#   - savings_analyzer: weekly Cost Explorer Savings Plans/RI recommendations.
#   - resource_cleanup: weekly sweep of unattached volumes, old snapshots and
#                        unassociated EIPs.
# See iam.tf for their roles/policies and lambda.tf for the functions/log
# groups/schedules themselves.

data "aws_caller_identity" "current" {}

locals {
  environment_tag = var.tags["Environment"]
  name            = "${local.environment_tag}-${var.name}"
  account_id      = data.aws_caller_identity.current.account_id

  # ARNs built manually from known inputs (region/account id/name), never
  # read back from the not-yet-created resource's own computed attribute:
  # the AWS provider marks a to-be-created resource's computed attributes
  # unknown until apply, which would make every IAM policy referencing them
  # (iam.tf) unknown too, and unusable in a plan-only `terraform test` run
  # (see this repo's stepfunctions component, which precomputes
  # local.state_machine_arn the same way for the same reason).
  scheduler_log_group_arn        = "arn:aws:logs:${var.region}:${local.account_id}:log-group:/aws/lambda/${local.name}-scheduler:*"
  savings_analyzer_log_group_arn = "arn:aws:logs:${var.region}:${local.account_id}:log-group:/aws/lambda/${local.name}-savings-analyzer:*"
  resource_cleanup_log_group_arn = "arn:aws:logs:${var.region}:${local.account_id}:log-group:/aws/lambda/${local.name}-resource-cleanup:*"
  cost_alerts_topic_arn          = "arn:aws:sns:${var.region}:${local.account_id}:${local.name}-cost-alerts"

  # Cost optimization settings per lifecycle tier (var.environment, from
  # settings.context.stage - see variables.tf). var.environment is validated
  # to exactly these three keys, so a direct index is safe: an unrecognized
  # value fails plan instead of silently falling back to dev's settings.
  optimization_settings = {
    dev = {
      auto_shutdown   = true
      use_spot        = true
      spot_percentage = 70
      # EventBridge schedule expressions are the 6-field cron(min hour dom
      # month dow year) form, with '?' in whichever of day-of-month/day-of-week
      # is not used - a 5-field Unix cron string is rejected at apply time
      # ("Parameter ScheduleExpression is not valid").
      schedule_on  = "0 7 ? * MON-FRI *"
      schedule_off = "0 19 ? * MON-FRI *"
      enable_ri    = false
      enable_sp    = false
    }
    staging = {
      auto_shutdown   = true
      use_spot        = true
      spot_percentage = 50
      schedule_on     = "0 6 ? * MON-FRI *"
      schedule_off    = "0 20 ? * MON-FRI *"
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

  current_settings = local.optimization_settings[var.environment]

  # Mutating scheduler/cleanup IAM actions are conditioned on the target
  # resource carrying tags.Environment AND one of these opt-in tag values, so
  # a resource must be deliberately opted in before this component can
  # start/stop or delete it - being tagged with the stack's Environment alone
  # is not enough. See iam.tf.
  opt_in_tag_key             = "CostOptimization"
  scheduler_opt_in_tag_value = "scheduled"
  cleanup_opt_in_tag_value   = "cleanup-eligible"
}

# ========================================
# Cost Anomaly Detection
# ========================================

resource "aws_ce_anomaly_monitor" "main" {
  name              = "${local.name}-cost-monitor"
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "SERVICE"

  tags = { Name = "${local.name}-cost-monitor" }
}

resource "aws_ce_anomaly_subscription" "main" {
  name      = "${local.name}-cost-anomaly-subscription"
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

  tags = { Name = "${local.name}-cost-anomaly-subscription" }
}

# ========================================
# Budget Alerts
# ========================================

resource "aws_budgets_budget" "monthly" {
  name         = "${local.name}-monthly-budget"
  budget_type  = "COST"
  limit_amount = var.monthly_budget_limit
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name = "TagKeyValue"
    values = [
      # AWS Budgets matches user-defined cost-allocation tags as
      # "user:<Key>$<Value>" (AWS-owned tags use "aws:..."); the Environment
      # tag must also be activated as a cost allocation tag in the payer
      # account, or no spend will be attributed to it - see README.
      "user:Environment$${local.environment_tag}"
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
# CloudWatch Dashboard for Cost Monitoring
# ========================================

resource "aws_cloudwatch_dashboard" "cost_optimization" {
  dashboard_name = "${local.name}-cost-optimization"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/Billing", "EstimatedCharges", "Currency", "USD", { stat = "Maximum", label = "Current Month Charges" }]
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
