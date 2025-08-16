# Cost Optimization Module Outputs

output "instance_scheduler_function_name" {
  description = "Name of the Lambda function for instance scheduling"
  value       = try(aws_lambda_function.scheduler[0].function_name, null)
}

output "instance_scheduler_function_arn" {
  description = "ARN of the Lambda function for instance scheduling"
  value       = try(aws_lambda_function.scheduler[0].arn, null)
}

output "savings_analyzer_function_name" {
  description = "Name of the Lambda function for savings analysis"
  value       = aws_lambda_function.savings_analyzer.function_name
}

output "savings_analyzer_function_arn" {
  description = "ARN of the Lambda function for savings analysis"
  value       = aws_lambda_function.savings_analyzer.arn
}

output "resource_cleanup_function_name" {
  description = "Name of the Lambda function for resource cleanup"
  value       = aws_lambda_function.resource_cleanup.function_name
}

output "resource_cleanup_function_arn" {
  description = "ARN of the Lambda function for resource cleanup"
  value       = aws_lambda_function.resource_cleanup.arn
}

output "cost_anomaly_monitor_arn" {
  description = "ARN of the cost anomaly monitor"
  value       = aws_ce_anomaly_monitor.main.arn
}

output "cost_anomaly_subscription_arn" {
  description = "ARN of the cost anomaly subscription"
  value       = aws_ce_anomaly_subscription.main.arn
}

output "monthly_budget_id" {
  description = "ID of the monthly budget"
  value       = aws_budgets_budget.monthly.id
}

output "monthly_budget_limit" {
  description = "Monthly budget limit in USD"
  value       = aws_budgets_budget.monthly.limit_amount
}

output "cost_alerts_topic_arn" {
  description = "ARN of the SNS topic for cost alerts"
  value       = aws_sns_topic.cost_alerts.arn
}

output "cost_dashboard_url" {
  description = "URL to the CloudWatch cost optimization dashboard"
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${aws_cloudwatch_dashboard.cost_optimization.dashboard_name}"
}

output "optimization_settings" {
  description = "Current cost optimization settings for the environment"
  value = {
    environment     = var.environment
    auto_shutdown   = local.current_settings.auto_shutdown
    use_spot        = local.current_settings.use_spot
    spot_percentage = local.current_settings.spot_percentage
    schedule_on     = local.current_settings.schedule_on
    schedule_off    = local.current_settings.schedule_off
    enable_ri       = local.current_settings.enable_ri
    enable_sp       = local.current_settings.enable_sp
  }
}

output "estimated_monthly_savings" {
  description = "Estimated monthly savings from optimization settings"
  value = {
    auto_shutdown_savings = local.current_settings.auto_shutdown ? "~30% for non-production resources" : "0%"
    spot_instance_savings = local.current_settings.use_spot ? "~${70 - local.current_settings.spot_percentage}% on compute costs" : "0%"
    note                  = "Actual savings depend on usage patterns and workload characteristics"
  }
}

output "start_schedule_rule_arn" {
  description = "ARN of the CloudWatch Event Rule for starting instances"
  value       = try(aws_cloudwatch_event_rule.start_instances[0].arn, null)
}

output "stop_schedule_rule_arn" {
  description = "ARN of the CloudWatch Event Rule for stopping instances"
  value       = try(aws_cloudwatch_event_rule.stop_instances[0].arn, null)
}

output "cleanup_schedule_rule_arn" {
  description = "ARN of the CloudWatch Event Rule for resource cleanup"
  value       = aws_cloudwatch_event_rule.cleanup.arn
}

output "savings_analysis_schedule_rule_arn" {
  description = "ARN of the CloudWatch Event Rule for savings analysis"
  value       = aws_cloudwatch_event_rule.savings_analysis.arn
}

output "cost_optimization_policies" {
  description = "Cost optimization policies and thresholds"
  value = {
    budget_alert_threshold     = "80%"
    scale_down_cpu_threshold   = "${var.scale_down_threshold}%"
    scale_up_cpu_threshold     = "${var.scale_up_threshold}%"
    snapshot_retention_days    = var.snapshot_retention_days
    s3_ia_transition_days      = var.s3_ia_transition_days
    s3_glacier_transition_days = var.s3_glacier_transition_days
    rds_backup_retention_days  = var.rds_backup_retention_period
  }
}

output "notification_configuration" {
  description = "Notification configuration for cost alerts"
  value = {
    budget_emails = var.budget_notification_emails
    anomaly_email = var.cost_anomaly_notification_email
    alert_emails  = var.cost_alert_emails
    sns_topic_arn = aws_sns_topic.cost_alerts.arn
  }
  sensitive = true
}

output "cleanup_configuration" {
  description = "Resource cleanup configuration"
  value = {
    dry_run_mode           = var.cleanup_dry_run
    cleanup_unused_volumes = var.cleanup_unused_volumes
    cleanup_old_snapshots  = var.cleanup_old_snapshots
    cleanup_unused_eips    = var.cleanup_unused_eips
    schedule               = "Weekly on Sunday at 2 AM UTC"
  }
}

output "recommendations" {
  description = "Cost optimization recommendations based on current configuration"
  value = {
    consider_reserved_instances = !local.current_settings.enable_ri && var.environment == "prod" ? "Consider purchasing Reserved Instances for production workloads" : null
    consider_savings_plans      = !local.current_settings.enable_sp && var.environment == "prod" ? "Consider Savings Plans for predictable compute usage" : null
    enable_spot_instances       = !local.current_settings.use_spot ? "Enable spot instances for fault-tolerant workloads" : null
    implement_auto_shutdown     = !local.current_settings.auto_shutdown && var.environment != "prod" ? "Implement auto-shutdown for non-production resources" : null
  }
}