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
| region, tags (must include `Environment`) | create_dashboard, create_sns_topic, enable_certificate_monitoring + certificate_arns/certificate_domains, enable_synthetic_monitoring, enable_tracing, business_metric_filters/business_metric_alarms | log_group_names/arns, dashboard_name, sns_topic_arn, {cpu,memory,db_connection,lambda_error}_alarm_names — not consumed via `!terraform.state` by any other component today |

## Dependencies & gotchas

- Depends on `vpc/main` + `acm/main` (main instance), `vpc/main` +
  `acm/services` (data instance).
- `tags` must include an `Environment` key (validated) — also used to build
  the `BusinessMetrics/<Environment>` namespace.
- `certificate_arns`/`certificate_domains` come from acm outputs via a
  `// {}` fallback, so this still plans cleanly with empty maps if acm has
  no certs yet.
- Alarms only send notifications if `create_sns_topic = true`; alarm
  actions reference `aws_sns_topic.alarms[0]` conditionally.

## Usage

```
atmos terraform plan monitoring/main -s fnx-dev-testenv-01
atmos terraform plan monitoring/data -s fnx-prod-production
```
