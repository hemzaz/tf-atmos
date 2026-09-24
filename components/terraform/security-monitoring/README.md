# security-monitoring

Routes security findings to an SNS topic. EventBridge rules send GuardDuty
findings of severity 4.0 and above (MEDIUM, HIGH and CRITICAL), failed HIGH and
CRITICAL Security Hub control findings and, optionally, HIGH and CRITICAL
Inspector V2 findings to the topic. The component also creates CloudWatch
alarms, email subscriptions and an optional Lambda alert-enrichment function
for Slack and PagerDuty.

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
    - component: guardduty/main
    - component: securityhub/main
vars:
  guardduty_detector_id: !terraform.state guardduty/main .detector_id
  securityhub_account_arn: !terraform.state securityhub/main .account_arn
  enable_inspector: false
```

## Inputs / outputs

| Key | Notes |
|---|---|
| `tags` (required) | must contain `Environment` key (validated) |
| `guardduty_detector_id` | from `guardduty/main .detector_id`; null turns the GuardDuty rule and alarm off (validated format) |
| `securityhub_account_arn` | from `securityhub/main .account_arn`; null turns the Security Hub rule off (must be a `hub/default` ARN) |
| `enable_inspector` | enables Inspector V2 and its rule. Catalog default is `false` because Inspector bills per resource scanned |
| `security_email_subscriptions`, `slack_webhook_url`, `pagerduty_integration_key` | alert routing |
| out: `guardduty_detector_id`, `security_hub_account_arn` | pass-throughs of the consumed IDs |
| out: `security_alerts_topic_arn`, `*_event_rule_arn` | — |

## Dependencies / gotchas

- Deploy `guardduty/main` and `securityhub/main` first. If they have no state
  when this component is planned, `!terraform.state` yields null and the
  matching route is planned as off. Re-plan after they are applied to add it.
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
