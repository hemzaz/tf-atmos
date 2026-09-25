# Metric alarms, dashboards and Logs Insights queries on any namespace and
# dimensions. The fixed-purpose inputs elsewhere in this component assume a
# resource shape (API Gateway alarms use the REST ApiName dimension, for one);
# these take the metric exactly as CloudWatch publishes it, so an HTTP API
# (ApiId), an event bus (EventBusName) or a table (TableName) can be watched.

resource "aws_cloudwatch_metric_alarm" "metric" {
  for_each = var.metric_alarms

  alarm_name          = "${local.name_prefix}-${each.key}"
  alarm_description   = coalesce(each.value.description, "${each.value.namespace} ${each.value.metric_name} ${each.value.comparison_operator} ${each.value.threshold}")
  namespace           = each.value.namespace
  metric_name         = each.value.metric_name
  dimensions          = each.value.dimensions
  comparison_operator = each.value.comparison_operator
  threshold           = each.value.threshold
  evaluation_periods  = each.value.evaluation_periods
  period              = each.value.period
  statistic           = each.value.statistic
  extended_statistic  = each.value.extended_statistic
  treat_missing_data  = each.value.treat_missing_data
  alarm_actions       = var.create_sns_topic ? [aws_sns_topic.alarms[0].arn] : []
  ok_actions          = var.create_sns_topic ? [aws_sns_topic.alarms[0].arn] : []

  tags = { Name = "${local.name_prefix}-${each.key}" }
}

# Each widget is 12 wide and 6 high, two per row, in the order given.
resource "aws_cloudwatch_dashboard" "metric" {
  for_each = var.metric_dashboards

  dashboard_name = "${local.name_prefix}-${each.key}"
  dashboard_body = jsonencode({
    widgets = [
      for i, w in each.value.widgets : {
        type   = "metric"
        x      = (i % 2) * 12
        y      = floor(i / 2) * 6
        width  = 12
        height = 6
        properties = {
          title  = w.title
          region = var.region
          period = w.period
          stat   = w.stat
          view   = "timeSeries"
          metrics = [
            for m in w.metrics : concat(
              [m.namespace, m.metric],
              flatten([for k in sort(keys(m.dimensions)) : [k, m.dimensions[k]]]),
            )
          ]
        }
      }
    ]
  })
}

resource "aws_cloudwatch_query_definition" "this" {
  for_each = var.log_insights_queries

  name            = "${local.name_prefix}/${each.key}"
  log_group_names = each.value.log_group_names
  query_string    = each.value.query
}
