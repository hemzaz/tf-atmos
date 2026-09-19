# security-monitoring

Creates a GuardDuty detector (+ S3/EKS/malware protection features and a
high-severity finding filter), enables Security Hub with CIS/FSBP/PCI-DSS
standards subscriptions, enables Inspector V2, an SNS topic for security
alerts (with optional Slack/PagerDuty via a Lambda alert-enrichment
function), EventBridge rules routing GuardDuty/Security Hub/Inspector
findings to SNS, and CloudWatch alarms on finding thresholds.

## Deployed instances

Not referenced by any of the 3 real stacks — zero instances. Separately, the
prod stack's `security.yaml` has `guardduty/main` and `securityhub/main`
entries, both `enabled: false` placeholders for a future, not-yet-written
dedicated component — not this component, does not exercise this code.

## Inputs / outputs

| Key | Notes |
|---|---|
| `tags` (required) | must contain `Environment` key (validated) |
| `guardduty_finding_frequency` | one of FIFTEEN_MINUTES/ONE_HOUR/SIX_HOURS (validated) |
| `enable_guardduty`, `enable_security_hub`, `enable_inspector` | each independently toggleable |
| `security_email_subscriptions`, `slack_webhook_url`, `pagerduty_integration_key` | alert routing |
| out: `guardduty_detector_id`, `security_hub_account_arn`, `security_alerts_topic_arn` | — |

## Dependencies / gotchas

- No `dependencies.components` entries exist anywhere (component is unused).
- Do not confuse with the disabled `guardduty/main`/`securityhub/main` stack stubs in prod — those belong to a different, not-yet-built component.
- `tags` validation fails the plan if `Environment` key is missing.
- Security Hub standards (`enable_cis_standard` etc.) are separate subscriptions — `enable_security_hub` alone enables no standard.

## Usage

```
atmos terraform plan security-monitoring -s fnx-dev-testenv-01
```
(after adding a `security-monitoring` component entry to that stack).
