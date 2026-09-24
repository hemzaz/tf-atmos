# monitoring

Creates CloudWatch log groups/dashboards, an SNS alarm topic with email
subscriptions, EC2/RDS/Lambda/EKS/ALB/ElastiCache metric alarms, an ACM
certificate-expiry dashboard + alarm, an API-Gateway/EKS/ALB "backend
services" dashboard, an optional Synthetics canary (+ its IAM execution
role), an optional X-Ray sampling rule, and arbitrary business-metric log
filters/alarms from `business_metric_filters`/`business_metric_alarms`.

## Deployed

`monitoring/main` and `monitoring/data` in all 3 real stacks
(fnx-dev-testenv-01, fnx-staging-staging-01, fnx-prod-production).
`monitoring/main` watches `acm/main` certificates; `monitoring/data` watches
`acm/services` certificates.

| Inputs (required) | Inputs (behavior) | Outputs |
|---|---|---|
| region, tags (must have a non-empty `Environment` value) | create_dashboard, create_sns_topic, enable_certificate_monitoring + certificate_arns/certificate_domains, enable_synthetic_monitoring, enable_tracing, business_metric_filters/business_metric_alarms, metric_alarms, metric_dashboards, log_insights_queries | log_group_names/arns, dashboard_name, sns_topic_arn, {cpu,memory,db_connection,lambda_error,metric}_alarm_names, metric_dashboard_names — not consumed via `!terraform.state` by any other component today |

## Any metric: `metric_alarms`, `metric_dashboards`, `log_insights_queries`

The fixed-purpose inputs assume a resource shape. For example, the API
Gateway alarms use the REST `ApiName` dimension, which an HTTP API does not
publish. These three inputs (`metrics.tf`) take a metric exactly as
CloudWatch publishes it, by namespace, metric name and dimensions.

| Input | Creates | Notes |
|---|---|---|
| `metric_alarms` (map) | `aws_cloudwatch_metric_alarm` `<Environment>-<key>` | exactly one of `statistic` (SampleCount/Average/Sum/Minimum/Maximum) or `extended_statistic` (`p99`, ...); `period` 300 and `evaluation_periods` 2 by default; notifies the SNS topic (alarm and OK) when `create_sns_topic` |
| `metric_dashboards` (map of `widgets`) | `aws_cloudwatch_dashboard` `<Environment>-<key>` | each widget is one time-series graph of its `metrics` (`namespace`, `metric`, `dimensions`), 12x6, two per row; the body is built with `jsonencode`, dimensions sorted by name |
| `log_insights_queries` (map) | `aws_cloudwatch_query_definition` `<Environment>/<key>` | `log_group_names` (at least one) and `query` |

Example (stack YAML):

```yaml
metric_alarms:
  api-5xx:
    namespace: AWS/ApiGateway
    metric_name: 5xx
    dimensions:
      ApiId: !terraform.state apigateway/main .http_api_id
    comparison_operator: GreaterThanThreshold
    threshold: 10
    statistic: Sum
```

Tests: `tests/metrics.tftest.hcl`, run against a mock provider with
`terraform init -backend=false && terraform test`.

## Dependencies & gotchas

- Depends on `vpc/main` + `acm/main` (main instance), `vpc/main` +
  `acm/services` (data instance).
- `tags` must have a non-empty `Environment` value (validated) — also used to
  build the `BusinessMetrics/<Environment>` namespace.
- `certificate_arns`/`certificate_domains` come from acm outputs via a
  `// {}` fallback, so this still plans cleanly with empty maps if acm has
  no certs yet.
- `enable_tracing` creates an X-Ray sampling rule `<Environment>-backend-services`
  (10% fixed rate), cut to X-Ray's 32-character limit. It used to be
  `<Environment>-monitoring-backend-services`, over the limit in every stack.
- Alarms only send notifications if `create_sns_topic = true`; alarm
  actions reference `aws_sns_topic.alarms[0]` conditionally.

## Usage

```
atmos terraform plan monitoring/main -s fnx-dev-testenv-01
atmos terraform plan monitoring/data -s fnx-prod-production
```
