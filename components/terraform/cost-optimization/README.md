# cost-optimization

Deploys three scheduled Lambda functions plus supporting IAM roles, EventBridge
rules and SNS: an instance scheduler (`lambda/scheduler.py`, start/stop by
business hours), a savings-plan/RI analyzer, and a resource-cleanup function
(unused EBS volumes, old snapshots, unused EIPs). Also creates a Cost
Explorer anomaly monitor + subscription, a monthly `aws_budgets_budget`, and
an SNS topic for cost alerts.

## Deployed instances

Not currently deployed in any of the 3 real stacks (fnx-dev-testenv-01,
fnx-staging-staging-01, fnx-prod-production) — zero instances in the stack
maps. Add a `cost-optimization` entry to a stack's `components.terraform`
before this applies.

## Inputs / outputs

| Key | Notes |
|---|---|
| `namespace` (required) | 3-19 chars (validated) |
| `environment` (required) | one of dev/staging/prod (validated) |
| `monthly_budget_limit` (required) | numeric string (validated) |
| `budget_notification_emails`, `cost_alert_emails`, `cost_anomaly_notification_email` | validated as email addresses |
| `cleanup_dry_run` | string `"true"`/`"false"` (not a real bool — validated as one of those strings) |
| out: `instance_scheduler_function_arn`, `savings_analyzer_function_arn`, `resource_cleanup_function_arn`, `cost_alerts_topic_arn` | — |

## Dependencies / gotchas

- No `dependencies.components` entries exist anywhere (component is unused).
- `cleanup_dry_run` is typed `string` not `bool` — YAML booleans fail validation; must be quoted `"true"`/`"false"` (defaults to `"true"`).
- Every numeric/threshold var (retention days, spot price %, Aurora capacity, S3 lifecycle) has a range validation — see variables.tf.

## Usage

```
atmos terraform plan cost-optimization -s fnx-dev-testenv-01
```
(after adding a `cost-optimization` component entry to that stack).
