# CloudWatch Dashboards with Real JSON Templates
# Provides comprehensive visibility into infrastructure, security, cost, and performance

locals {
  dashboard_vars = {
    region      = var.region
    environment = var.environment
    account_id  = data.aws_caller_identity.current.account_id
  }
}

data "aws_caller_identity" "current" {}

# Infrastructure Overview Dashboard
resource "aws_cloudwatch_dashboard" "infrastructure" {
  count = var.create_infrastructure_dashboard ? 1 : 0

  dashboard_name = "${var.environment}-infrastructure-overview"

  dashboard_body = templatefile(
    "${path.module}/templates/infrastructure-dashboard.json.tpl",
    local.dashboard_vars
  )
}

# Security Dashboard
resource "aws_cloudwatch_dashboard" "security" {
  count = var.create_security_dashboard ? 1 : 0

  dashboard_name = "${var.environment}-security-monitoring"

  dashboard_body = templatefile(
    "${path.module}/templates/security-dashboard.json.tpl",
    local.dashboard_vars
  )
}

# Cost Optimization Dashboard
resource "aws_cloudwatch_dashboard" "cost" {
  count = var.create_cost_dashboard ? 1 : 0

  dashboard_name = "${var.environment}-cost-optimization"

  dashboard_body = templatefile(
    "${path.module}/templates/cost-dashboard.json.tpl",
    local.dashboard_vars
  )
}

# Performance Dashboard
resource "aws_cloudwatch_dashboard" "performance" {
  count = var.create_performance_dashboard ? 1 : 0

  dashboard_name = "${var.environment}-performance-metrics"

  dashboard_body = templatefile(
    "${path.module}/templates/performance-dashboard.json.tpl",
    local.dashboard_vars
  )
}

# Application Dashboard
resource "aws_cloudwatch_dashboard" "application" {
  count = var.create_application_dashboard ? 1 : 0

  dashboard_name = "${var.environment}-application-metrics"

  dashboard_body = templatefile(
    "${path.module}/templates/application-dashboard.json.tpl",
    local.dashboard_vars
  )
}

# Backend Services Dashboard
resource "aws_cloudwatch_dashboard" "backend" {
  count = var.create_backend_dashboard ? 1 : 0

  dashboard_name = "${var.environment}-backend-services"

  dashboard_body = templatefile(
    "${path.module}/templates/backend-dashboard.json.tpl",
    local.dashboard_vars
  )
}

# Certificate Monitoring Dashboard
resource "aws_cloudwatch_dashboard" "certificates" {
  count = var.create_certificate_dashboard ? 1 : 0

  dashboard_name = "${var.environment}-certificate-monitoring"

  dashboard_body = templatefile(
    "${path.module}/templates/certificate-dashboard.json.tpl",
    local.dashboard_vars
  )
}

# Custom Dashboard (user-provided JSON)
resource "aws_cloudwatch_dashboard" "custom" {
  for_each = var.custom_dashboards

  dashboard_name = "${var.environment}-${each.key}"
  dashboard_body = each.value.body
}

# Dashboard URLs output
output "dashboard_urls" {
  description = "URLs to access CloudWatch Dashboards"
  value = {
    infrastructure = var.create_infrastructure_dashboard ? "https://console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${aws_cloudwatch_dashboard.infrastructure[0].dashboard_name}" : null
    security      = var.create_security_dashboard ? "https://console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${aws_cloudwatch_dashboard.security[0].dashboard_name}" : null
    cost          = var.create_cost_dashboard ? "https://console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${aws_cloudwatch_dashboard.cost[0].dashboard_name}" : null
    performance   = var.create_performance_dashboard ? "https://console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${aws_cloudwatch_dashboard.performance[0].dashboard_name}" : null
    application   = var.create_application_dashboard ? "https://console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${aws_cloudwatch_dashboard.application[0].dashboard_name}" : null
    backend       = var.create_backend_dashboard ? "https://console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${aws_cloudwatch_dashboard.backend[0].dashboard_name}" : null
    certificates  = var.create_certificate_dashboard ? "https://console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${aws_cloudwatch_dashboard.certificates[0].dashboard_name}" : null
  }
}

# Dashboard names
output "dashboard_names" {
  description = "Names of created CloudWatch Dashboards"
  value = {
    infrastructure = var.create_infrastructure_dashboard ? aws_cloudwatch_dashboard.infrastructure[0].dashboard_name : null
    security      = var.create_security_dashboard ? aws_cloudwatch_dashboard.security[0].dashboard_name : null
    cost          = var.create_cost_dashboard ? aws_cloudwatch_dashboard.cost[0].dashboard_name : null
    performance   = var.create_performance_dashboard ? aws_cloudwatch_dashboard.performance[0].dashboard_name : null
    application   = var.create_application_dashboard ? aws_cloudwatch_dashboard.application[0].dashboard_name : null
    backend       = var.create_backend_dashboard ? aws_cloudwatch_dashboard.backend[0].dashboard_name : null
    certificates  = var.create_certificate_dashboard ? aws_cloudwatch_dashboard.certificates[0].dashboard_name : null
    custom        = { for k, v in aws_cloudwatch_dashboard.custom : k => v.dashboard_name }
  }
}
