# monitoring

Creates CloudWatch log groups/dashboards, a KMS-encryptable SNS alarm topic
with email subscriptions, EC2/RDS/Lambda/EKS/ALB/ElastiCache metric alarms,
an ACM certificate-expiry dashboard + alarm, an API-Gateway/EKS/ALB "backend
services" dashboard, an optional Synthetics canary (+ its IAM execution
role), an optional X-Ray sampling rule, and arbitrary business-metric log
filters/alarms from `business_metric_filters`/`business_metric_alarms`.

## Naming: `name` (Cloud Posse null-label style)

Every resource this component creates is named `<tags.Environment>-<name>-<suffix>`
(the `local.name_prefix` local), not `tags.Environment` alone — mirroring the
`id = ...-name` pattern from [cloudposse/terraform-null-label](https://github.com/cloudposse/terraform-null-label).
`name` defaults to `"monitoring"` and must be lowercase alphanumeric/hyphens
(validated).

Two instances of this component run in every real stack. Before `name`
existed, both built every resource from `tags.Environment` alone, so the
second instance's apply failed with `ResourceAlreadyExists` on the SNS
topic, dashboard and alarms (they're separate Terraform states creating the
same-named AWS objects). Each instance below sets a distinct `name` to fix
this; `tests/names.tftest.hcl` proves two different `name` values produce
disjoint topic/dashboard/alarm names.

## Deployed

`monitoring/main` (`name: main`) and `monitoring/data` (`name: data`) in all
3 real stacks (fnx-dev-testenv-01, fnx-staging-staging-01,
fnx-prod-production), each with `kms_key_id: !terraform.state kms/main
.key_arn` and `kms/main` in `dependencies.components`.
`monitoring/main` watches `acm/main` certificates; `monitoring/data` watches
`acm/services` certificates. `stacks/catalog/templates/*.yaml` and
`localemu` run a single, unnamed instance that keeps the `name` default.

| Inputs (required) | Inputs (behavior) | Outputs |
|---|---|---|
| region, tags (must have a non-empty `Environment` value) | name, kms_key_id, create_dashboard, create_sns_topic, enable_certificate_monitoring + certificate_arns/certificate_domains, enable_synthetic_monitoring, enable_tracing, business_metric_filters/business_metric_alarms, metric_alarms, metric_dashboards, log_insights_queries | log_group_names/arns, dashboard_name, sns_topic_arn, {cpu,memory,db_connection,lambda_error,metric}_alarm_names, metric_dashboard_names — not consumed via `!terraform.state` by any other component today |

## Overview dashboard dimensions

`aws_cloudwatch_dashboard.main` (`create_dashboard`) is built with
`jsonencode` in HCL, not `templatefile`, the same way the certificate
dashboard is (#166). Each widget plots real per-resource dimensions instead
of one metric averaged over the whole account, and a widget whose backing
list is empty is dropped rather than rendered with an empty `metrics: []`:

| Input | Widget | Dimension |
|---|---|---|
| `rds_instances` | RDS CPU Utilization | `DBInstanceIdentifier` |
| `ecs_clusters` | ECS CPU Utilization | `ClusterName` |
| `lambda_functions` | Lambda Invocations | `FunctionName` |
| `load_balancers` | Load Balancer Requests | `LoadBalancer` (accepts a full ELB ARN or the short `app/<name>/<id>` form) |
| `elasticache_clusters` | ElastiCache CPU Utilization | `CacheClusterId` |
| `eks_cluster_name` | EKS Node CPU Utilization | `ClusterName` |
| `api_gateway_name` + `api_gateway_stages` | API Gateway Requests | `ApiName` + `Stage` |

Named `<name_prefix>-overview`, not `-infrastructure-overview`: `dashboards.tf`
also has an `aws_cloudwatch_dashboard.infrastructure`
(`create_infrastructure_dashboard`, on by default) named
`<name_prefix>-infrastructure-overview`. Both default on, so before this
rename enabling both flags made two separate Terraform resources manage the
exact same CloudWatch dashboard name; `-overview` gives `create_dashboard`
its own name so `create_infrastructure_dashboard` is the sole owner of
`-infrastructure-overview`.

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

Tests: `tests/metrics.tftest.hcl`, `tests/names.tftest.hcl`, run against a
mock provider with `terraform init -backend=false && terraform test`.

## Dependencies & gotchas

- Depends on `vpc/main` + `acm/main` + `kms/main` (main instance), `vpc/main`
  + `acm/services` + `kms/main` (data instance).
- `tags` must have a non-empty `Environment` value (validated) — also used to
  build the `BusinessMetrics/<Environment>` namespace.
- `kms_key_id` (a KMS key ARN, validated) encrypts `aws_cloudwatch_log_group.main`
  and `aws_sns_topic.alarms`; each real stack instance sets it from
  `!terraform.state kms/main .key_arn`, whose key policy already allows
  CloudWatch alarms to publish to encrypted topics
  (`catalog/kms/defaults.yaml` `allow_cloudwatch_alarms`). Not set in the
  abstract `monitoring/defaults` catalog: 5 `stacks/catalog/templates/*.yaml`
  also inherit it and declare their own `dependencies.components` without
  `kms/main`, so a shared default there would reference an undeclared
  dependency for them (`workflows/scripts/common/check-dependencies.py`).
  Null (the default) leaves both unencrypted.
- `certificate_arns`/`certificate_domains` come from acm outputs via a
  `// {}` fallback, so this still plans cleanly with empty maps if acm has
  no certs yet.
- The templated dashboards (`templates/*.json.tpl`) used to leave a trailing
  comma after the last row of every non-empty list, so listing any RDS
  instance, Lambda, load balancer, ECS or cache cluster failed the plan with
  "dashboard_body contains an invalid JSON". Rows are now comma-separated;
  `tests/metrics.tftest.hcl` renders every dashboard with several of each.
- `enable_tracing` creates an X-Ray sampling rule
  `<Environment>-<name>-backend-services` (10% fixed rate), cut to X-Ray's
  32-character limit (`substr`). It used to be built from `Environment` alone
  and collided between `main`/`data`.
- Alarms only send notifications if `create_sns_topic = true`; alarm
  actions reference `aws_sns_topic.alarms[0]` conditionally.

## Usage

```
atmos terraform plan monitoring/main -s fnx-dev-testenv-01
atmos terraform plan monitoring/data -s fnx-prod-production
```
