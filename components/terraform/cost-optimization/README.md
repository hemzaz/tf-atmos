# cost-optimization

Three scheduled Lambda functions with their roles, EventBridge rules, log groups and error alarms:
a start/stop scheduler for EC2, RDS and Auto Scaling Groups (only when the stage's `auto_shutdown`
is on), a weekly savings analyzer (Cost Explorer and Compute Optimizer recommendations), and a
weekly cleanup of unattached EBS volumes, old snapshots and unassociated Elastic IPs. Also a Cost
Explorer anomaly monitor, a monthly budget, a cost-alerts SNS topic and a dashboard. There is no
Cloud Posse equivalent; the Lambdas are packaged like Cloud Posse `aws-lambda` (`archive` zip).

## Wiring

- Instance: `cost-optimization/main` in the three AWS stacks; reads `kms/main .key_arn` (log groups
  and SNS topic). Deploys in the `monitoring` layer.

## Notes

- Mutating actions only touch resources tagged with the stack's `Environment` and an opt-in tag:
  `CostOptimization=scheduled` (scheduler) or `CostOptimization=cleanup-eligible` (cleanup).
- Cleanup runs in dry-run mode by default: `cleanup_dry_run` is a quoted string `"true"`/`"false"`,
  not a YAML boolean.
- The budget filters on the user-defined `Environment` cost allocation tag. Activate it in the payer
  account's Billing console, or the budget stays at about $0 and never alerts.
- `environment` is the lifecycle tier (`dev`/`staging`/`prod`), not `tags.Environment`.
- Handlers re-raise errors so the Lambda `Errors` alarms can fire (EventBridge ignores return values).
