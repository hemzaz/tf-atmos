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

Each instance also wires the dashboard/alarm dimension inputs from the
sources the same stack actually deploys, via `!terraform.state`, so the
infrastructure and backend dashboards plot real data instead of empty
widgets:

| Stack | Instance | Watches |
|---|---|---|
| fnx-dev-testenv-01 | `monitoring/main` | `eks/main` (`eks_cluster_name`), `rds/main` (`rds_instances`), `ecs/main` (`ecs_clusters`), `apigateway/main` (`api_gateway_name`/`api_gateway_stages`) |
| fnx-dev-testenv-01 | `monitoring/data` | `eks/data`, `rds/data`, `apigateway/data`, `lambda/data-processor` (`lambda_functions`) |
| fnx-staging-staging-01 | `monitoring/main` | `eks/main`, `rds/main`, `ecs/main`, `apigateway/main` |
| fnx-staging-staging-01 | `monitoring/data` | `eks/data`, `rds/data`, `apigateway/data`, `lambda/data-processor`, `lambda/data-transformer` |
| fnx-prod-production | `monitoring/main` | `eks/main`, `rds/main`, `ecs/main`, `apigateway/main`, `elasticache/main` (`elasticache_clusters`) |
| fnx-prod-production | `monitoring/data` | `eks/data`, `rds/data`, `apigateway/data`, `lambda/data-processor`, `lambda/data-transformer`, `lambda/report-generator` |

`apigateway`'s `api_gateway_name` is read from its `api_name` output
(`!terraform.state apigateway/main .api_name`), not repeated as a literal, so
it always matches the API Gateway that instance actually creates.

| Inputs (required) | Inputs (behavior) | Outputs |
|---|---|---|
| region, tags (must have a non-empty `Environment` value) | name, kms_key_id, create_infrastructure_dashboard/create_performance_dashboard/create_application_dashboard/create_security_dashboard/create_cost_dashboard/create_certificate_dashboard, create_dashboard (legacy alias of create_infrastructure_dashboard), create_sns_topic, enable_certificate_monitoring + certificate_arns/certificate_domains, enable_backend_monitoring, enable_synthetic_monitoring, enable_tracing, business_metric_filters/business_metric_alarms, metric_alarms, metric_dashboards, log_insights_queries | log_group_names/arns, dashboard_name (the infrastructure dashboard), dashboard_urls/dashboard_names (all dashboards, `dashboards.tf`), sns_topic_arn, {cpu,memory,db_connection,lambda_error,metric}_alarm_names, metric_dashboard_names — not consumed via `!terraform.state` by any other component today |

## Dashboard dimensions

`aws_cloudwatch_dashboard.infrastructure`, `.performance`, `.application` and
`.backend_services` (`create_infrastructure_dashboard`/
`create_performance_dashboard`/`create_application_dashboard`/
`enable_backend_monitoring`, in `dashboards.tf`'s `local.dashboard_specs`/
`local.dashboard_bodies`) are built with `jsonencode` in HCL, not
`templatefile`, the same way the certificate dashboard is (#166). Each widget
plots real per-resource dimensions instead of one metric averaged over the
whole account, and a widget whose backing list is empty is dropped rather
than rendered with an empty `metrics: []`. `security` and `cost` stay on
`templatefile`: every metric they plot (`CloudTrailMetrics`, GuardDuty,
Security Hub, `AWS/Billing`) is inherently account/region-wide, with no
per-resource list in this component's inputs to dimension it by.

| Input | Infrastructure widget | Performance widget | Application widget | Backend widget | Dimension |
|---|---|---|---|---|---|
| `rds_instances` | RDS CPU Utilization | RDS Read/Write Latency | RDS Database Connections | RDS CPU, Connections & Latency | `DBInstanceIdentifier` |
| `ecs_clusters` | ECS CPU Utilization | ECS CPU Utilization | — | — | `ClusterName` |
| `lambda_functions` | Lambda Invocations | Lambda Duration (p99) | Lambda Errors, Lambda Duration | Lambda Duration, Errors & Throttles | `FunctionName` |
| `load_balancers` | Load Balancer Requests | ALB Target Response Time | ALB Target 5XX Errors | Application Load Balancers | `LoadBalancer` (accepts a full ELB ARN or the short `app/<name>/<id>` form) |
| `elasticache_clusters` | ElastiCache CPU Utilization | ElastiCache Freeable Memory | ElastiCache Cache Hits | ElastiCache Performance | `CacheClusterId` |
| `eks_cluster_name` (+ `backend_services_namespace` for backend) | EKS Node CPU Utilization | EKS Pod CPU Utilization | — | EKS Backend Services (Container Insights) | `ClusterName` (+ `Namespace` for backend) |
| `api_gateway_name` + `api_gateway_stages` | API Gateway Requests | API Gateway Latency | API Gateway Requests & 5XX Errors | API Gateway Requests, Latency & Errors | `ApiName` + `Stage` |
| `business_metric_filters` | — | — | — | Business Metrics | none (`BusinessMetrics/<Environment>`, `<name_prefix>_<key>`) |

`aws_cloudwatch_dashboard.infrastructure` used to have a duplicate:
`aws_cloudwatch_dashboard.main` (`create_dashboard`, renamed to
`<name_prefix>-overview` at one point) built the same widgets under a second
Terraform resource. `create_infrastructure_dashboard` defaults to `true` and
every real stack instance also set `create_dashboard: true`, so each
instance managed the same content twice, under two different CloudWatch
dashboard names. `aws_cloudwatch_dashboard.main` has been removed —
`aws_cloudwatch_dashboard.infrastructure` (`<name_prefix>-infrastructure-overview`)
is the sole dashboard resource now, created when *either*
`create_dashboard` or `create_infrastructure_dashboard` is `true`.
`create_dashboard` is kept as a distinct variable (a legacy alias, not
folded into `create_infrastructure_dashboard`) only because
`stacks/catalog/templates/*.yaml` and every real-stack
`monitoring/main`/`monitoring/data` instance still set it — removing it
would turn those into undeclared-variable warnings for a file this fix is
not allowed to edit.

The backend services dashboard had the same duplicate-resource history, plus
a second bug: `aws_cloudwatch_dashboard.backend_services`
(`enable_backend_monitoring`, `main.tf`, on by default) and
`aws_cloudwatch_dashboard.backend` (`create_backend_dashboard`,
`dashboards.tf`, off by default) named the *exact same* dashboard
(`<name_prefix>-backend-services`); turning on `create_backend_dashboard`
would have made two Terraform resources manage one CloudWatch object, each
apply overwriting the other's state. `aws_cloudwatch_dashboard.backend` and
`create_backend_dashboard` have been removed; `enable_backend_monitoring` is
the sole owner. Separately, its old `templates/backend-dashboard.json.tpl`
hardcoded `ApiName`/`ClusterName` to `var.api_gateway_name`/
`var.eks_cluster_name` with no `""` guard, and its Lambda/RDS/ALB/ElastiCache
widgets rendered an empty metrics list on every real stack — none of them
wired `lambda_functions`/`rds_instances`/`load_balancers`/
`elasticache_clusters` into this component (see Deployed above, now fixed).
`aws_cloudwatch_dashboard.backend_services` is now built from
`local.dashboard_bodies["backend"]` the same jsonencode way as the other
three dashboards, and the template file has been removed. Its fake Logs
Insights and X-Ray widgets, and a Billing/TrustedAdvisor row duplicating the
`cost` dashboard, were dropped rather than reproduced.

The certificate dashboard had the identical duplicate-resource pattern:
`aws_cloudwatch_dashboard.certificate_monitoring` (`enable_certificate_monitoring`,
`main.tf`) and `aws_cloudwatch_dashboard.certificates`
(`create_certificate_dashboard`, `dashboards.tf`) rendered the same
`local.certificate_dashboard_body` under two different names
(`<name_prefix>-certificates` vs `<name_prefix>-certificate-monitoring`).
`aws_cloudwatch_dashboard.certificates` has been removed;
`aws_cloudwatch_dashboard.certificate_monitoring`
(`<name_prefix>-certificates`) is created when *either*
`enable_certificate_monitoring` or `create_certificate_dashboard` is `true`.

## Any metric: `metric_alarms`, `metric_dashboards`, `log_insights_queries`

The fixed-purpose inputs assume a resource shape. For example, the API
Gateway alarms use the REST `ApiName` dimension, which an HTTP API does not
publish. These three inputs (`metrics.tf`) take a metric exactly as
CloudWatch publishes it, by namespace, metric name and dimensions.

| Input | Creates | Notes |
|---|---|---|
| `metric_alarms` (map) | `aws_cloudwatch_metric_alarm` `<name_prefix>-<key>` | exactly one of `statistic` (SampleCount/Average/Sum/Minimum/Maximum) or `extended_statistic` (`p99`, ...); `period` 300 and `evaluation_periods` 2 by default; notifies the SNS topic (alarm and OK) when `create_sns_topic` |
| `metric_dashboards` (map of `widgets`) | `aws_cloudwatch_dashboard` `<name_prefix>-<key>` | each widget is one time-series graph of its `metrics` (`namespace`, `metric`, `dimensions`), 12x6, two per row; the body is built with `jsonencode`, dimensions sorted by name |
| `log_insights_queries` (map) | `aws_cloudwatch_query_definition` `<name_prefix>/<key>` | `log_group_names` (at least one) and `query` |

`<name_prefix>` is `<tags.Environment>-<name>` (see Naming above); these
three used to build names from `tags.Environment` alone, so two instances of
this component setting the same `metric_alarms`/`metric_dashboards`/
`log_insights_queries` key would have hit the same `ResourceAlreadyExists`
collision the `name` variable exists to prevent.

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

- Every instance depends on `vpc/main` + `kms/main`, plus `acm/main` (main
  instance) or `acm/services` (data instance), plus whatever it watches for
  dashboard/alarm dimensions — `eks/*`, `rds/*`, `apigateway/*`, and
  per-instance/per-stack extras (`ecs/main` and, in prod, `elasticache/main`
  for `monitoring/main`; `lambda/*` for `monitoring/data`). See the Deployed
  table above for the exact `dependencies.components` list per stack and
  instance.
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
- The remaining templated dashboards (`templates/{security,cost}-dashboard.json.tpl`)
  used to leave a trailing comma after the last row of every non-empty list,
  so listing any RDS instance, Lambda, load balancer, ECS or cache cluster
  failed the plan with "dashboard_body contains an invalid JSON". Rows are
  now comma-separated; `tests/metrics.tftest.hcl` renders every dashboard
  with several of each. `infrastructure`/`performance`/`application`/`backend`
  are no longer `templatefile`-based (see Dashboard dimensions above), so
  they cannot hit this class of bug — `templates/backend-dashboard.json.tpl`
  has been removed.
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
