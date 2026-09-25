variable "region" {
  type        = string
  description = "AWS region"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-\\d+$", var.region))
    error_message = "The region must be a valid AWS region name (e.g., us-east-1, eu-west-1)."
  }
}

variable "environment" {
  type        = string
  description = "Environment name (dev, staging, prod)"
  default     = "dev"
}

# Cloud Posse null-label style (terraform-null-label: id = ...-name): every
# named resource in this component is "<tags.Environment>-<name>-<suffix>"
# rather than "<tags.Environment>-<suffix>" alone. Two instances of this
# component run in every real stack (monitoring/main, monitoring/data); before
# this variable existed they both named resources from Environment alone and
# collided on the second apply (SNS topic, dashboards and alarms all
# ResourceAlreadyExists). Set a distinct value per instance (e.g. "main",
# "data").
variable "name" {
  type        = string
  description = "Per-instance name, combined with tags.Environment to build every resource name (<Environment>-<name>-<suffix>). Co-located instances of this component must use distinct values."
  default     = "monitoring"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.name))
    error_message = "name must be non-empty, lowercase alphanumeric characters and hyphens, and must not start or end with a hyphen."
  }
}

# Dashboard Configuration Variables
variable "create_infrastructure_dashboard" {
  type        = bool
  description = "Create infrastructure overview dashboard"
  default     = true
}

variable "create_security_dashboard" {
  type        = bool
  description = "Create security monitoring dashboard"
  default     = true
}

variable "create_cost_dashboard" {
  type        = bool
  description = "Create cost optimization dashboard"
  default     = false
}

variable "create_performance_dashboard" {
  type        = bool
  description = "Create performance metrics dashboard"
  default     = true
}

variable "create_application_dashboard" {
  type        = bool
  description = "Create application metrics dashboard"
  default     = false
}

variable "create_certificate_dashboard" {
  type        = bool
  description = "Create certificate monitoring dashboard"
  default     = false
}

variable "custom_dashboards" {
  type = map(object({
    body = string
  }))
  description = "Custom CloudWatch dashboards (name => dashboard JSON body)"
  default     = {}
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
  description = "KMS key ARN (kms/main's key_arn) encrypting CloudWatch log groups (aws_cloudwatch_log_group.main) and the alarm SNS topic (aws_sns_topic.alarms). Its key policy must let cloudwatch.amazonaws.com publish to encrypted topics (kms allow_cloudwatch_alarms). Null leaves both unencrypted."
  default     = null

  validation {
    condition     = var.kms_key_id == null || can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/[a-zA-Z0-9-]+$", var.kms_key_id))
    error_message = "kms_key_id must be a KMS key ARN (arn:aws:kms:<region>:<account>:key/<id>), or null."
  }
}

variable "create_dashboard" {
  type = bool
  # Legacy alias of create_infrastructure_dashboard, not a second dashboard:
  # it used to gate a separate Terraform resource
  # (aws_cloudwatch_dashboard.main, "-overview") that duplicated
  # aws_cloudwatch_dashboard.infrastructure (create_infrastructure_dashboard,
  # true by default) - every real stack instance set create_dashboard: true,
  # so each apply managed the same dashboard content twice, under two
  # different CloudWatch names. There is now a single resource
  # (aws_cloudwatch_dashboard.infrastructure); either this or
  # create_infrastructure_dashboard being true creates it. Kept as a distinct
  # variable (not merged into create_infrastructure_dashboard) because
  # stacks/catalog/templates/*.yaml and every real-stack
  # monitoring/main+monitoring/data instance still set it; removing it would
  # turn those into undeclared-variable warnings for a file this change is
  # not allowed to edit.
  description = "Legacy alias of create_infrastructure_dashboard: either being true creates the infrastructure overview dashboard. Kept only so existing stack configs that set it remain valid."
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
  description = "Tags to apply to resources; must include Environment (used in resource names)"

  validation {
    condition     = trimspace(lookup(var.tags, "Environment", "")) != ""
    error_message = "tags must include a non-empty Environment value."
  }
}

# Certificate monitoring variables
variable "enable_certificate_monitoring" {
  type        = bool
  description = "Whether to enable certificate monitoring dashboard and alarms"
  default     = false
}

# FIXED: Removed duplicate eks_cluster_name declaration
# This variable is used for both certificate and backend monitoring
variable "eks_cluster_name" {
  type        = string
  description = "EKS cluster name for monitoring (certificate and backend services)"
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

  # Empty string, not null. enable_backend_monitoring defaults true, so
  # aws_cloudwatch_dashboard.backend_services renders backend-dashboard.json.tpl
  # on every instance, and that template interpolates this value directly:
  #   templates/backend-dashboard.json.tpl:11
  #     ["AWS/ApiGateway", "Count", "ApiName", "${api_gateway_name}"]
  # Terraform refuses to interpolate null - "Invalid template interpolation
  # value; The expression result is null" - so a null default made every
  # instance fail at PLAN time, and dev, staging and prod all leave it unset.
  # The sibling eks_cluster_name already defaults to "" and feeds the same
  # template; this now matches it.
  default = ""
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
    period              = number
    statistic           = string
    threshold           = number
    description         = string
  }))
  description = "Business metric alarm configurations"
  default     = {}
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
