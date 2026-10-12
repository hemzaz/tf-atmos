# cost-optimization

Three scheduled Lambda functions with their roles, EventBridge rules, log groups and error alarms:
a start/stop scheduler for EC2, RDS and Auto Scaling Groups (only when the stage's `auto_shutdown`
is on), a weekly savings analyzer (Cost Explorer and Compute Optimizer recommendations), and a
weekly cleanup of unattached EBS volumes, old snapshots and unassociated Elastic IPs. Also a Cost
Explorer anomaly monitor, a monthly budget, a cost-alerts SNS topic and a dashboard. There is no
Cloud Posse equivalent; the Lambdas are packaged like Cloud Posse `aws-lambda` (`archive` zip).

## Wiring

- Instance: `cost-optimization/main` in one stack per account (dev, staging, `fnx-ue1-prod`,
  `fnx-ew1-prod`); reads `kms/main .key_arn` (log groups and SNS topic). Deploys in the
  `monitoring` layer.
- `billing_notifications_sns_enabled` (`fnx-ew1-prod`, a GDPR stack): the budget and the anomaly
  subscription notify the in-region cost-alerts topic, whose `cost_alert_emails` subscriptions
  deliver them, instead of `budget_notification_emails` and `cost_anomaly_notification_email`
  (which must then be unset). The global Budgets and Cost Explorer services (us-east-1) store only
  the topic ARN. The topic gets a policy for `budgets.amazonaws.com`, `costalerts.amazonaws.com`
  and this region's CloudWatch alarms; its key needs `kms` `allow_billing_notifications`.
  `check-data-residency.py` fails a GDPR stack that sets the two email inputs.

## Notes

- Mutating actions only touch resources tagged with the stack's `Environment` and an opt-in tag:
  `CostOptimization=scheduled` (scheduler) or `CostOptimization=cleanup-eligible` (cleanup).
- Cleanup runs in dry-run mode by default: `cleanup_dry_run` is a quoted string `"true"`/`"false"`,
  not a YAML boolean.
- The budget filters on the user-defined `Environment` cost allocation tag: the stack's own value
  plus `budget_additional_environment_tags` (the prod primaries add their DR standby, `ue2`/`ec1`,
  which has no budget of its own; lint `check-dr-pairs` fails a standby missing there). Activate the tag in the payer account's Billing console, or the
  budget stays at about $0 and never alerts.
- `environment` is the lifecycle tier (`dev`/`staging`/`prod`), not `tags.Environment`.
- In an EU stack, the savings analyzer's Cost Explorer calls and the dashboard's `AWS/Billing`
  widget are served from us-east-1: account billing metadata only, no personal data, and in
  component code, so `check-data-residency.py` cannot see it.
- AWS takes an SNS anomaly subscriber only at `IMMEDIATE` frequency, so the SNS path sends each
  anomaly (20% impact threshold) as it is found; the email path stays `DAILY`.
- Handlers re-raise errors so the Lambda `Errors` alarms can fire (EventBridge ignores return values).
