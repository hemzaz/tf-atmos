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
| `public_subnets_additional_tags`, `private_subnets_additional_tags` | extra tags on every public / private subnet (Cloud Posse's names), e.g. the `kubernetes.io/role/elb` and `kubernetes.io/cluster/<name>` tags EKS load balancers discover subnets by; `Name` is refused |

Outputs `vpc_id`, `private_subnet_ids`, `public_subnet_ids` are consumed across
`dns`, `ec2`, `eks`, `monitoring`, `rds`, `securitygroup` and `services` catalog defaults.

## Dependencies / gotchas

- No entries in `dependencies.components` point at `vpc` — downstream components read
  its state directly via `!terraform.state vpc/main|services ...` instead.
- `database_subnet_ids` is exported; there is no elasticache subnet tier (no
  variable, no resource), so cache components use `private_subnet_ids`.
- `tags` without a non-empty `Environment` value fails validation before any plan.

## Usage

```
atmos terraform plan vpc/main -s fnx-dev-testenv-01
atmos terraform plan vpc/services -s fnx-prod-production
```

## Tests

`tests/subnet_tags.tftest.hcl` runs against a mock provider:
`terraform init -backend=false && terraform test`.
