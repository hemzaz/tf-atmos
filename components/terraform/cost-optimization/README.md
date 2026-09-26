# cost-optimization

No Cloud Posse component exists for this. Each Lambda function is packaged
the way Cloud Posse's [aws-lambda](https://github.com/cloudposse-terraform-components/aws-lambda)
component does it: a local zip built by the `archive` provider with
`source_code_hash` driving replacement. IAM policies are built with
`jsonencode()`, as in this repo's `lambda` and `stepfunctions` components.

Deploys three scheduled Lambda functions plus supporting IAM roles,
EventBridge rules, CloudWatch log groups and SNS:

- **`lambda/scheduler.py`** - starts/stops EC2 instances, RDS instances and
  Auto Scaling Groups on a per-stage schedule. Only created when the stage's
  `auto_shutdown` setting is on (dev/staging; off in prod).
- **`lambda/savings_analyzer.py`** - weekly Cost Explorer Savings
  Plans/Reserved Instance/rightsizing recommendations plus Compute Optimizer
  recommendations, published to the cost-alerts SNS topic.
- **`lambda/cleanup.py`** - weekly sweep of unattached EBS volumes, old EBS
  snapshots and unassociated Elastic IPs. Honors `DRY_RUN` (the default):
  candidates are logged and published to SNS, nothing is deleted.

Also creates a Cost Explorer anomaly monitor + subscription, a monthly
`aws_budgets_budget`, an SNS topic for cost alerts, and a CloudWatch
dashboard.

## Deployed instances

One `cost-optimization/main` instance per stack (`fnx-dev-testenv-01`,
`fnx-staging-staging-01`, `fnx-prod-production`) - see
`stacks/catalog/cost-optimization/defaults.yaml` and each stack's
`services.yaml`.

## Naming

Cloud Posse null-label style: every resource is named
`<tags.Environment>-<name>-<suffix>` (e.g. `testenv-01-main-scheduler`).

## Least privilege

Every IAM statement is one of:

- a read-only `Describe*`/`List*`/`Get*` statement, `Resource "*"` and no
  `Condition` - those actions have no resource-level permission support;
- a mutating statement (start/stop/scale/delete) scoped by a `Condition` on
  the target resource's own tags: `tags.Environment` **and** an opt-in tag
  (`CostOptimization=scheduled` for the scheduler,
  `CostOptimization=cleanup-eligible` for cleanup). A resource must be
  deliberately tagged into this component's blast radius before it can be
  started/stopped/scaled/deleted - being in the stack's Environment alone is
  not enough. The condition key namespace is service-specific: EC2 has its
  own `ec2:ResourceTag/<key>`; RDS, EKS, Auto Scaling and ELB do not, and use
  the `aws:ResourceTag/<key>` global key instead;
- a `logs` statement scoped to the function's own CloudWatch log group
  (never the account-wide `arn:aws:logs:*:*:*`); or
- an SNS `Publish` + matching KMS `GenerateDataKey`/`Decrypt` statement,
  scoped by the encryption context SNS sets on the call
  (`kms:EncryptionContext:aws:sns:topicArn`), mirroring the grant pattern
  this repo's `stepfunctions` component uses for its own KMS usage.

Every ARN referenced from an IAM policy is built manually from known inputs
(region/account id/name) rather than read back from the not-yet-created
resource's own computed attribute, for the same reason `stepfunctions`
precomputes `local.state_machine_arn`: the AWS provider marks a to-be-created
resource's computed attributes unknown until apply, which would make the
policy referencing them unknown too.

**To opt a real resource in**, tag it with `Environment = <the stack's tag
value>` and `CostOptimization = scheduled` (for the scheduler to start/stop
it) or `CostOptimization = cleanup-eligible` (for cleanup to delete it once
it is unattached/old/unassociated).

## Encryption

The Lambda functions' CloudWatch log groups and the cost-alerts SNS topic
are encrypted with `kms_key_arn` (kms/main). kms/main already allows
`logs.<region>.amazonaws.com` to use the key (`allow_cloudwatch_logs` in
`catalog/kms/defaults.yaml`); the SNS-publishing Lambda roles (savings
analyzer, cleanup) get their own scoped KMS grant instead of a kms/main
`allow_*` flag, since the principal here is an IAM role this component
creates, not an AWS service principal.

## Inputs / outputs

| Key | Notes |
|---|---|
| `name` (default `main`) | combined with `tags.Environment` to build every resource name |
| `tags` (required) | must include a non-empty `Environment` |
| `environment` (required) | one of `dev`/`staging`/`prod` - the **lifecycle tier** (from `settings.context.stage`), not `tags.Environment`; selects the per-stage schedule/auto-shutdown settings |
| `kms_key_arn` (required) | validated as a KMS key ARN |
| `monthly_budget_limit` (required) | numeric string (validated) |
| `budget_notification_emails`, `cost_alert_emails`, `cost_anomaly_notification_email` | validated as email addresses |
| `cleanup_dry_run` | string `"true"`/`"false"` (not a real bool - validated as one of those strings) |
| out: `instance_scheduler_function_arn`, `savings_analyzer_function_arn`, `resource_cleanup_function_arn`, `cost_alerts_topic_arn` | - |

## Dependencies / gotchas

- Reads `kms/main` via `!terraform.state`; declared in
  `stacks/catalog/cost-optimization/defaults.yaml`'s `dependencies.components`.
- `cleanup_dry_run` is typed `string` not `bool` - YAML booleans fail
  validation; must be quoted `"true"`/`"false"` (defaults to `"true"`).
- Every numeric/threshold var (retention days, spot price %, S3 lifecycle)
  has a range validation - see `variables.tf`.

## Usage

```
atmos terraform plan cost-optimization/main -s fnx-dev-testenv-01
```
