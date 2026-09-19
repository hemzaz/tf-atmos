output "dashboard_arn" {
  description = "ARN of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.main.dashboard_arn
}

output "dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.main.dashboard_name
}

output "dashboard_url" {
  description = "Console URL for the CloudWatch dashboard"
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=${local.region}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}

output "discovered_instance_count" {
  description = "Number of EC2 instances discovered for monitoring"
  value       = var.enable_auto_discovery ? length(data.aws_instances.discovered[0].ids) : 0
}

output "discovered_alb_count" {
  description = "Number of ALBs discovered for monitoring"
  value       = length(data.aws_lb.discovered)
}

output "custom_namespace" {
  description = "Custom CloudWatch namespace for metrics"
  value       = var.custom_namespace
}
