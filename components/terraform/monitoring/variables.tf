variable "region" {
  type        = string
  description = "AWS region"
}

variable "log_groups" {
  type = map(object({
    retention_days = number
  }))
  description = "Map of log groups to create"
  default     = {}
}

variable "kms_key_id" {
  type        = string
  description = "KMS key ID for log encryption"
  default     = null
}

variable "create_dashboard" {
  type        = bool
  description = "Whether to create CloudWatch dashboard"
  default     = false
}

variable "vpc_id" {
  type        = string
  description = "VPC ID for dashboard metrics"
  default     = ""
}

variable "rds_instances" {
  type        = list(string)
  description = "List of RDS instances to monitor"
  default     = []
}

variable "ecs_clusters" {
  type        = list(string)
  description = "List of ECS clusters to monitor"
  default     = []
}

variable "lambda_functions" {
  type        = list(string)
  description = "List of Lambda functions to monitor"
  default     = []
}

variable "load_balancers" {
  type        = list(string)
  description = "List of load balancers to monitor"
  default     = []
}

variable "elasticache_clusters" {
  type        = list(string)
  description = "List of ElastiCache clusters to monitor"
  default     = []
}

variable "create_sns_topic" {
  type        = bool
  description = "Whether to create an SNS topic for alarms"
  default     = true
}

variable "alarm_email_subscriptions" {
  type        = list(string)
  description = "List of email addresses to notify for alarms"
  default     = []
}

variable "cpu_alarms" {
  type = map(object({
    namespace          = string
    evaluation_periods = number
    period             = number
    threshold          = number
    dimensions         = map(string)
  }))
  description = "Map of CPU alarms to create"
  default     = {}
}

variable "memory_alarms" {
  type = map(object({
    namespace          = string
    evaluation_periods = number
    period             = number
    threshold          = number
    dimensions         = map(string)
  }))
  description = "Map of memory alarms to create"
  default     = {}
}

variable "db_connection_alarms" {
  type = map(object({
    evaluation_periods = number
    period             = number
    threshold          = number
  }))
  description = "Map of database connection alarms to create"
  default     = {}
}

variable "lambda_error_alarms" {
  type = map(object({
    evaluation_periods = number
    period             = number
    threshold          = number
  }))
  description = "Map of Lambda error alarms to create"
  default     = {}
}

variable "log_metric_filters" {
  type = map(object({
    log_group_name     = string
    pattern            = string
    evaluation_periods = number
    period             = number
    threshold          = number
  }))
  description = "Map of log metric filters to create"
  default     = {}
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to resources"
  default     = {}
}

# Certificate monitoring variables
variable "enable_certificate_monitoring" {
  type        = bool
  description = "Whether to enable certificate monitoring dashboard and alarms"
  default     = false
}

variable "eks_cluster_name" {
  type        = string
  description = "EKS cluster name for certificate management monitoring"
  default     = ""
}

variable "certificate_arns" {
  type        = list(string)
  description = "List of certificate ARNs to monitor"
  default     = []
}

variable "certificate_names" {
  type        = list(string)
  description = "List of certificate names corresponding to the ARNs"
  default     = []
}

variable "certificate_domains" {
  type        = list(string)
  description = "List of certificate domain names"
  default     = []
}

variable "certificate_statuses" {
  type        = list(string)
  description = "List of certificate statuses"
  default     = []
}

variable "certificate_expiry_dates" {
  type        = list(string)
  description = "List of certificate expiry dates in human-readable format"
  default     = []
}

variable "certificate_alarm_arns" {
  type        = list(string)
  description = "List of certificate alarm ARNs to display in dashboard"
  default     = []
}

variable "certificate_expiry_threshold" {
  type        = number
  description = "Threshold in days for certificate expiry alarms"
  default     = 30
}

# Backend Services Monitoring Variables
variable "enable_backend_monitoring" {
  type        = bool
  description = "Enable comprehensive backend services monitoring"
  default     = true
}

variable "api_gateway_name" {
  type        = string
  description = "API Gateway name for monitoring"
  default     = null
}

variable "api_gateway_stages" {
  type        = list(string)
  description = "API Gateway stages to monitor"
  default     = []
}

variable "api_gateway_latency_threshold" {
  type        = number
  description = "API Gateway latency alarm threshold in milliseconds"
  default     = 1000
}

variable "api_gateway_error_threshold" {
  type        = number
  description = "API Gateway error count alarm threshold"
  default     = 10
}

variable "eks_cluster_name" {
  type        = string
  description = "EKS cluster name for monitoring"
  default     = null
}

variable "backend_services_namespace" {
  type        = string
  description = "Kubernetes namespace for backend services"
  default     = "backend-services"
}

variable "eks_failed_requests_threshold" {
  type        = number
  description = "EKS cluster failed requests alarm threshold"
  default     = 10
}

variable "eks_pod_cpu_threshold" {
  type        = number
  description = "EKS pod CPU utilization alarm threshold percentage"
  default     = 80
}

variable "eks_pod_memory_threshold" {
  type        = number
  description = "EKS pod memory utilization alarm threshold percentage"
  default     = 85
}

variable "alb_response_time_threshold" {
  type        = number
  description = "ALB response time alarm threshold in seconds"
  default     = 1.0
}

variable "alb_unhealthy_hosts_threshold" {
  type        = number
  description = "ALB unhealthy hosts alarm threshold"
  default     = 0
}

variable "elasticache_cpu_threshold" {
  type        = number
  description = "ElastiCache CPU utilization alarm threshold percentage"
  default     = 75
}

variable "elasticache_memory_threshold" {
  type        = number
  description = "ElastiCache free memory alarm threshold in bytes"
  default     = 50000000 # 50MB
}

# Synthetic Monitoring Variables
variable "enable_synthetic_monitoring" {
  type        = bool
  description = "Enable synthetic monitoring with CloudWatch Synthetics"
  default     = false
}

variable "synthetics_bucket" {
  type        = string
  description = "S3 bucket for synthetics artifacts"
  default     = null
}

variable "synthetics_schedule" {
  type        = string
  description = "Schedule expression for synthetics canary"
  default     = "rate(5 minutes)"
}

variable "api_endpoint" {
  type        = string
  description = "API endpoint for synthetic monitoring"
  default     = null
}

# Distributed Tracing Variables
variable "enable_tracing" {
  type        = bool
  description = "Enable X-Ray distributed tracing"
  default     = false
}

# Business Metrics Variables
variable "business_metric_filters" {
  type = map(object({
    log_group_name = string
    pattern        = string
    value          = string
  }))
  description = "Business metric filters for custom CloudWatch metrics"
  default     = {}
}

variable "business_metric_alarms" {
  type = map(object({
    comparison_operator = string
    evaluation_periods  = number
    period             = number
    statistic          = string
    threshold          = number
    description        = string
  }))
  description = "Business metric alarm configurations"
  default     = {}
}

# Cost Monitoring Variables
variable "enable_cost_monitoring" {
  type        = bool
  description = "Enable cost monitoring alarms"
  default     = false
}

variable "daily_cost_threshold" {
  type        = number
  description = "Daily cost alarm threshold in USD"
  default     = 100
}

variable "monthly_cost_threshold" {
  type        = number
  description = "Monthly cost alarm threshold in USD"
  default     = 3000
}

# Security Monitoring Variables
variable "enable_security_monitoring" {
  type        = bool
  description = "Enable security-related monitoring"
  default     = false
}

variable "failed_login_threshold" {
  type        = number
  description = "Failed login attempts alarm threshold"
  default     = 10
}

variable "suspicious_activity_threshold" {
  type        = number
  description = "Suspicious activity alarm threshold"
  default     = 5
}

# Performance Baseline Variables
variable "enable_anomaly_detection" {
  type        = bool
  description = "Enable CloudWatch anomaly detection"
  default     = false
}

variable "anomaly_detection_metrics" {
  type        = list(string)
  description = "List of metrics to enable anomaly detection for"
  default     = []
}

# Multi-Region Monitoring
variable "enable_cross_region_monitoring" {
  type        = bool
  description = "Enable cross-region monitoring dashboards"
  default     = false
}

variable "monitored_regions" {
  type        = list(string)
  description = "List of regions to include in cross-region monitoring"
  default     = []
}