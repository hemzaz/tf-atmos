# security-monitoring

Routes security findings to an SNS topic encrypted with `kms/main`. EventBridge
rules send GuardDuty findings of severity 4.0 and above (MEDIUM, HIGH and
CRITICAL), new active failed HIGH and CRITICAL Security Hub control findings
and, optionally, HIGH and CRITICAL Inspector V2 findings to the topic. The
component also creates CloudWatch alarms, email subscriptions and an optional
Lambda alert-enrichment function for Slack and PagerDuty.

It does **not** create the GuardDuty detector or the Security Hub hub. Those
are owned by the `guardduty` and `securityhub` components (one component per
service, the Cloud Posse model). This component consumes their IDs.

## Deployed instances

`security-monitoring/main` in all three stacks (`components/security.yaml`),
inheriting the abstract `security-monitoring/defaults` from
`stacks/catalog/security-monitoring/defaults.yaml`. The catalog wires:

```yaml
dependencies:
  components:
    - component: kms/main
    - component: guardduty/main
    - component: securityhub/main
vars:
  guardduty_detector_id: !terraform.state guardduty/main .detector_id
  securityhub_account_arn: !terraform.state securityhub/main .account_arn
  require_guardduty_route: true
  require_securityhub_route: true
  kms_key_id: !terraform.state kms/main .key_arn
  enable_inspector: false
```

## Inputs / outputs

| Key | Notes |
|---|---|
| `tags` (required) | must contain `Environment` key (validated) |
| `guardduty_detector_id` | from `guardduty/main .detector_id` (validated format). Null fails the plan while `require_guardduty_route` is true; with it false, null turns the GuardDuty rule off |
| `securityhub_account_arn` | from `securityhub/main .account_arn` (must be a `hub/default` ARN). Null fails the plan while `require_securityhub_route` is true; with it false, null turns the Security Hub rule off |
| `require_guardduty_route`, `require_securityhub_route` | default `true` (and `true` in the catalog): a null ID is a precondition failure on the topic, so a first deploy fails loudly instead of silently turning alerting off |
| `kms_key_id` | from `kms/main .key_arn` (must be a key ARN); encrypts the topic. The key policy must allow `events.amazonaws.com` and `cloudwatch.amazonaws.com` (`kms` `allow_eventbridge` and `allow_cloudwatch_alarms`, on in `kms/defaults`) |
| `enable_inspector` | enables Inspector V2 and its rule. Catalog default is `false` because Inspector bills per resource scanned |
| `security_email_subscriptions`, `slack_webhook_url`, `pagerduty_integration_key` | alert routing |
| out: `guardduty_detector_id`, `security_hub_account_arn` | pass-throughs of the consumed IDs |
| out: `security_alerts_topic_arn`, `*_event_rule_arn` | — |

## Dependencies / gotchas

- Deploy `kms/main`, `guardduty/main` and `securityhub/main` first. If
  guardduty or securityhub has no state when this component is planned,
  `!terraform.state` yields null and the plan fails on the
  `require_*_route` precondition. Apply them, then re-plan.
- The topic policy lets only this account publish: `aws:SourceAccount` on
  both statements, plus `aws:SourceArn` limited to this account's EventBridge
  rules (`events:<region>:<account>:rule/*`) and CloudWatch alarms
  (`cloudwatch:<region>:<account>:alarm:*`).
- There is no GuardDuty CloudWatch alarm: GuardDuty publishes no
  `AWS/GuardDuty` findings metric. The EventBridge rule is the GuardDuty route.
- The Security Hub rule matches `RecordState: ACTIVE` and
  `Workflow.Status: NEW`, so archived and already-triaged findings do not
  re-alert on every re-import.
- The four `CloudTrailMetrics` alarms (root account usage, unauthorized API
  calls, IAM policy and security group changes) have no metric filter feeding
  them yet; that needs a CloudTrail trail delivering to CloudWatch Logs.
- The GuardDuty route uses EventBridge numeric matching (`>= 4`), so CRITICAL
  attack-sequence findings (9.0-10.0) are included. LOW findings stay in the
  console.
- The finding filters, protection plans and standards subscriptions belong to
  `guardduty` (`auto_archive_filter`, `enable_*_protection`) and `securityhub`
  (`standards`), not here.
- `tags` validation fails the plan if `Environment` key is missing.

## Usage

```
atmos terraform plan security-monitoring/main -s fnx-dev-testenv-01
```
