# vpc

Creates an `aws_vpc` with private/public/database subnets (keyed by CIDR, one per AZ
from `var.availability_zones`), an internet gateway, NAT gateway(s) (`single` or
`one_per_az`), route tables, network ACLs, default security group rules, optional
VPN/Transit Gateway attachment and RAM sharing, and optional VPC Flow Logs to CloudWatch
(own KMS key) with security alarms. Like Cloud Posse's `aws-vpc` it creates no IAM role.

Input names follow `cloudposse-terraform-components/aws-vpc` wherever an input maps one
to one. Inputs with no Cloud Posse counterpart (`nat_gateway_strategy`,
`enable_vpn_gateway`, `flow_logs_retention_days`, the flow-logs alarms, ...) keep their names.

## Deployed as

Real instances `vpc/main` and `vpc/services` in all 3 stacks: `fnx-dev-testenv-01`
(`10.0.0.0/16` / `10.1.0.0/16`), `fnx-staging-staging-01`, `fnx-prod-production`. Both
inherit abstract `vpc/defaults`; a plain abstract `vpc` catalog entry is not a real instance.

## Inputs / Outputs

| Input | Notes |
|---|---|
| `ipv4_primary_cidr_block`, `availability_zones`, `private_subnets`, `public_subnets` | required |
| `nat_gateway_enabled` | default true (Cloud Posse name) |
| `map_public_ip_on_launch` | default **false**, unlike Cloud Posse's true: instances in public subnets get a public IP only when a stack opts in |
| `vpc_flow_logs_enabled`, `vpc_flow_logs_traffic_type`, `vpc_flow_logs_max_aggregation_interval`, `vpc_flow_logs_format` | Cloud Posse names; logs go to CloudWatch, not Cloud Posse's S3 bucket component |
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
- The network ACLs allow inbound from `0.0.0.0/0` on the ephemeral ports (stateless
  return traffic) and, on public subnets, 80/443 for internet-facing load balancers.
  This is the documented exception to the "no inbound /0" rule; see `network-acls.tf`.

## Usage

```
atmos terraform plan vpc/main -s fnx-dev-testenv-01
atmos terraform plan vpc/services -s fnx-prod-production
```

## Tests

`tests/*.tftest.hcl` run against a mock provider:
`terraform init -backend=false && terraform test`.
