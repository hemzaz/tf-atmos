# Inputs for metrics.tf.

variable "metric_alarms" {
  type = map(object({
    namespace           = string
    metric_name         = string
    dimensions          = optional(map(string), {})
    comparison_operator = string
    threshold           = number
    evaluation_periods  = optional(number, 2)
    period              = optional(number, 300)
    statistic           = optional(string)
    extended_statistic  = optional(string)
    treat_missing_data  = optional(string, "missing")
    description         = optional(string)
  }))
  description = "Alarms on any CloudWatch metric, named <Environment>-<key>. Set exactly one of statistic (Average, Sum, ...) or extended_statistic (p99, ...). Notifies the SNS topic when create_sns_topic"
  default     = {}

  validation {
    condition     = alltrue([for a in values(var.metric_alarms) : (a.statistic == null) != (a.extended_statistic == null)])
    error_message = "Each metric_alarms entry must set exactly one of statistic or extended_statistic."
  }

  validation {
    condition = alltrue([for a in values(var.metric_alarms) : a.statistic == null || contains(
      ["SampleCount", "Average", "Sum", "Minimum", "Maximum"], coalesce(a.statistic, "Sum")
    )])
    error_message = "metric_alarms statistic must be SampleCount, Average, Sum, Minimum or Maximum; use extended_statistic for percentiles."
  }

  validation {
    condition = alltrue([for a in values(var.metric_alarms) : contains([
      "GreaterThanOrEqualToThreshold", "GreaterThanThreshold", "LessThanThreshold", "LessThanOrEqualToThreshold",
    ], a.comparison_operator)])
    error_message = "metric_alarms comparison_operator must be GreaterThanOrEqualToThreshold, GreaterThanThreshold, LessThanThreshold or LessThanOrEqualToThreshold."
  }

  validation {
    condition     = alltrue([for a in values(var.metric_alarms) : contains(["missing", "ignore", "breaching", "notBreaching"], a.treat_missing_data)])
    error_message = "metric_alarms treat_missing_data must be missing, ignore, breaching or notBreaching."
  }

  validation {
    condition     = alltrue([for a in values(var.metric_alarms) : a.period >= 10 && a.evaluation_periods >= 1])
    error_message = "metric_alarms period must be at least 10 seconds and evaluation_periods at least 1."
  }
}

variable "metric_dashboards" {
  type = map(object({
    widgets = list(object({
      title  = string
      period = optional(number, 300)
      stat   = optional(string, "Average")
      metrics = list(object({
        namespace  = string
        metric     = string
        dimensions = optional(map(string), {})
      }))
    }))
  }))
  description = "Dashboards of metric widgets, named <name_prefix>-<key>; each widget plots its metrics on one time series graph. key must not collide with a built-in dashboard's fixed name suffix (see validation)"
  default     = {}

  validation {
    condition     = alltrue(flatten([for d in values(var.metric_dashboards) : [for w in d.widgets : length(w.metrics) > 0]]))
    error_message = "Every metric_dashboards widget needs at least one metric."
  }

  # See the matching validation on custom_dashboards (variables.tf) for why:
  # metric_dashboards builds the exact same "<name_prefix>-<key>" dashboard
  # name as custom_dashboards and the built-in dashboards.
  validation {
    condition = alltrue([
      for k in keys(var.metric_dashboards) : !contains([
        "infrastructure-overview",
        "security-monitoring",
        "cost-optimization",
        "performance-metrics",
        "application-metrics",
        "certificates",
        "backend-services",
      ], k)
    ])
    error_message = "metric_dashboards keys must not collide with a built-in dashboard's fixed name suffix: infrastructure-overview, security-monitoring, cost-optimization, performance-metrics, application-metrics, certificates, backend-services."
  }
}

variable "log_insights_queries" {
  type = map(object({
    log_group_names = list(string)
    query           = string
  }))
  description = "Saved CloudWatch Logs Insights queries, named <Environment>/<key>, scoped to log_group_names"
  default     = {}

  validation {
    condition     = alltrue([for q in values(var.log_insights_queries) : length(q.log_group_names) > 0 && trimspace(q.query) != ""])
    error_message = "Each log_insights_queries entry needs at least one log group and a non-empty query."
  }
}
