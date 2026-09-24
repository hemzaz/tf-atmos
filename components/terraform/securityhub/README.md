# securityhub

Enables Security Hub for one account/region with consolidated control findings
and subscribes the compliance standards named in `standards`, building each ARN
from the short `<name>/v/<version>` path.

## Deployed

`securityhub/main` in all three stacks (`fnx-dev-testenv-01`,
`fnx-staging-staging-01`, `fnx-prod-production`), each in
`components/security.yaml`, inheriting the abstract `securityhub/defaults`
from `stacks/catalog/securityhub/defaults.yaml`. Every stack gets the default
standards (AWS FSBP v1.0.0 and CIS v1.2.0); only prod adds `pci-dss/v/3.2.1`.

| Inputs (required) | Inputs (behavior) | Outputs |
|---|---|---|
| region, tags (needs a non-empty `Environment`) | enable, enable_default_standards, standards | `account_id`, `account_arn` (the hub ARN, read by `security-monitoring/main`), `subscribed_standards_arns` |

## Dependencies & gotchas

- No `dependencies.components` of its own. `security-monitoring/defaults`
  lists `securityhub/main` as a dependency and reads `.account_arn`.
- `enable_default_standards = true` makes Security Hub subscribe AWS
  Foundational Security Best Practices v1.0.0 and CIS AWS Foundations
  Benchmark v1.2.0 itself. Those two are filtered out of `standards` so the
  component does not try to subscribe them a second time and fail on apply.
- `standards` takes short paths, not ARNs (`pci-dss/v/3.2.1`).
  `cis-aws-foundations-benchmark/v/1.2.0` is special-cased to the
  partition-wide `:::ruleset/` ARN; every other standard uses
  `:<region>::standards/`.
- `control_finding_generator` and `auto_enable_controls` are fixed, not inputs.
- This component is the only owner of the hub. `security-monitoring`
  consumes `account_arn` and enables no hub, and
  `workflows/scripts/security/harden.sh` deploys this component instead of
  calling `aws securityhub enable-security-hub`.
- Most Security Hub controls evaluate AWS Config recordings; without an AWS
  Config recorder in the account they report as failed or unavailable.

## Usage

```
atmos terraform plan securityhub/main -s fnx-prod-production
```
