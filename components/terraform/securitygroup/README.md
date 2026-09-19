# securitygroup

Creates one `aws_security_group` per entry in the `security_groups` map with
dynamic ingress/egress rule blocks (`main.tf`), plus optional CloudWatch
logging/alarms on security-group change events and a permissive-rule
(`0.0.0.0/0`) detector with a `terraform_data` precondition that can block
apply (`rules.tf`).

## Deployed instances

Not currently deployed in any of the 3 real stacks (fnx-dev-testenv-01,
fnx-staging-staging-01, fnx-prod-production) — zero instances in the stack
maps. Add a `securitygroup` entry to a stack's `components.terraform` before
this applies.

## Inputs / outputs

| Key | Notes |
|---|---|
| `vpc_id` (required) | — |
| `security_groups` (map, default `{}`) | keys become SG names; each value can set `ingress_rules`/`egress_rules`/`description`/`tags` |
| `tags["Environment"]` | used to build SG name `${Environment}-${key}-sg`; missing key errors at apply, not validated |
| `enforce_no_public_ingress` | when `true`, apply fails if any rule allows `0.0.0.0/0` ingress |
| `log_retention_days` | must be a valid CloudWatch retention value (validated) |
| out: `security_group_ids`, `security_group_arns` (both maps keyed by SG name) | — |

## Dependencies / gotchas

- No `dependencies.components` entries exist anywhere (component is unused).
- `tags` has no required-key validation, but the SG name/`Name` tag interpolate `var.tags["Environment"]` directly — omitting it fails at plan/apply, not with a clean validation error.
- `enforce_no_public_ingress = true` is a hard gate via `terraform_data` precondition, not just a warning.

## Usage

```
atmos terraform plan securitygroup -s fnx-dev-testenv-01
```
(after adding a `securitygroup` component entry to that stack).
