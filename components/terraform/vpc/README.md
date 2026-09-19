# vpc

Creates an `aws_vpc` with private/public/database subnets (keyed by CIDR, one per AZ
from `var.azs`), an internet gateway, NAT gateway(s) (`single` or `one_per_az`), route
tables, network ACLs, default security group rules, optional VPN/Transit Gateway
attachment and RAM sharing, an optional IAM role for VPC management, and optional VPC
Flow Logs to CloudWatch (own KMS key) with security alarms.

## Deployed as

Real instances `vpc/main` and `vpc/services` in all 3 stacks: `fnx-dev-testenv-01`
(`10.0.0.0/16` / `10.1.0.0/16`), `fnx-staging-staging-01`, `fnx-prod-production`. Both
inherit abstract `vpc/defaults`; a plain abstract `vpc` catalog entry is not a real instance.

## Inputs / Outputs

| Input | Notes |
|---|---|
| `vpc_cidr`, `azs`, `private_subnets`, `public_subnets` | required |
| `tags` / `nat_gateway_strategy` | tags must include a non-empty `Environment`; strategy is `single` or `one_per_az` |
| `manage_default_security_group` | default true: strips every rule from the VPC's AWS-created default SG (one way) |

Outputs `vpc_id`, `private_subnet_ids`, `public_subnet_ids` are consumed across
`dns`, `ec2`, `eks`, `monitoring`, `rds`, `securitygroup` and `services` catalog defaults.

## Dependencies / gotchas

- No entries in `dependencies.components` point at `vpc` — downstream components read
  its state directly via `!terraform.state vpc/main|services ...` instead.
- Stack configs reference `.database_subnet_ids`/`.elasticache_subnet_ids` on this
  component's state (`services.yaml`), but `outputs.tf` exports only
  `private_subnet_ids`/`public_subnet_ids` — neither exists (the latter isn't even a variable).
- `tags` without a non-empty `Environment` value fails validation before any plan.

## Usage

```
atmos terraform plan vpc/main -s fnx-dev-testenv-01
atmos terraform plan vpc/services -s fnx-prod-production
```
