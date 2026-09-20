# securityhub

Enables Security Hub for one account/region with consolidated control findings
and subscribes the compliance standards named in `standards`, building each ARN
from the short `<name>/v/<version>` path.

## Deployed

`securityhub/main` only, in fnx-prod-production
(`stacks/orgs/fnx/prod/eu-west-2/production/components/security.yaml`).
Grepping dev and staging stacks for `securityhub` finds no reference — those
environments don't deploy it today, so every input except `region`/`tags`
has a default.

| Inputs (required) | Inputs (behavior) | Outputs |
|---|---|---|
| region, tags (needs a non-empty `Environment`) | enable, enable_default_standards, standards | `account_id`, `account_arn`, `subscribed_standards_arns` — nothing reads these yet |

## Dependencies & gotchas

- No `dependencies.components` entries in the map.
- `enable_default_standards = true` makes Security Hub subscribe AWS
  Foundational Security Best Practices v1.0.0 and CIS AWS Foundations
  Benchmark v1.2.0 itself. Those two are filtered out of `standards` so the
  component does not try to subscribe them a second time and fail on apply;
  prod lists both and is relying on that filtering.
- `standards` takes short paths, not ARNs (`pci-dss/v/3.2.1`).
  `cis-aws-foundations-benchmark/v/1.2.0` is special-cased to the
  partition-wide `:::ruleset/` ARN; every other standard uses
  `:<region>::standards/`.
- `control_finding_generator` and `auto_enable_controls` are fixed, not inputs.
- This overlaps `security-monitoring`, which also manages
  `aws_securityhub_account`. Only one of the two may be enabled per
  account/region.

## Usage

```
atmos terraform plan securityhub/main -s fnx-prod-production
```
