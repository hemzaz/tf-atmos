# vpc

Creates an `aws_vpc` with private/public/database subnets (keyed by CIDR, one per AZ
from `var.availability_zones`), an internet gateway, NAT gateway(s) (`single` or
`one_per_az`), route tables, network ACLs, default security group rules, optional
VPN/Transit Gateway attachment and RAM sharing, and optional VPC Flow Logs to CloudWatch
(its own KMS key by default, or a caller's via `flow_logs_kms_key_arn`) with security
alarms. Like Cloud Posse's `aws-vpc` it creates no IAM role.

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
| `flow_logs_kms_key_arn` | empty (default) creates and uses this component's own key; a caller's ARN (e.g. `!terraform.state kms/main .key_arn`, set by `vpc/defaults`) is used instead and the component's own key is not created at all, since it would otherwise sit unused. Also encrypts `flow_logs_s3_backup`'s archive bucket. The given key needs an `allow_cloudwatch_logs`-style statement for `logs.<region>.amazonaws.com`, scoped by `kms:EncryptionContext:aws:logs:arn` |
| `tags` / `nat_gateway_strategy` | tags must include a non-empty `Environment`; strategy is `single` or `one_per_az` |
| `manage_default_security_group` | default true: strips every rule from the VPC's AWS-created default SG (one way) |
| `public_subnets_additional_tags`, `private_subnets_additional_tags` | extra tags on every public / private subnet (Cloud Posse's names), e.g. the `kubernetes.io/role/elb` and `kubernetes.io/cluster/<name>` tags EKS load balancers discover subnets by; `Name` is refused |
| `enable_vpc_endpoints`, `vpc_endpoints` | default `false` / `[]`. `vpc_endpoints` is a flat list of bare AWS PrivateLink service names (e.g. `secretsmanager`, `elasticache`, `s3`); the component classifies each one itself -- `s3` and `dynamodb` get a Gateway endpoint (route-table based, free), everything else an Interface endpoint (ENI + private DNS in the private subnets, behind a dedicated `<Environment>-vpce-sg` security group scoped to HTTPS from the VPC CIDR). Cloud Posse's `aws-vpc` splits these into two inputs (`interface_vpc_endpoints`, `vpc_gateway_endpoints`); this component keeps one list and does the split internally |

Outputs `vpc_id`, `private_subnet_ids`, `public_subnet_ids` are consumed across
`dns`, `ec2`, `eks`, `monitoring`, `rds`, `securitygroup` and `services` catalog defaults.

## Dependencies / gotchas

- `vpc/main` and `vpc/services` list `kms/main` in `dependencies.components` in every
  stack (`vpc/defaults` sets `flow_logs_kms_key_arn` from it) — `kms/main` is applied in
  an earlier deploy layer, so this needs no layer change.
- No other entries in `dependencies.components` point at `vpc` — downstream components
  read its state directly via `!terraform.state vpc/main|services ...` instead.
- `database_subnet_ids` is exported; there is no elasticache subnet tier (no
  variable, no resource), so cache components use `private_subnet_ids`.
- `tags` without a non-empty `Environment` value fails validation before any plan.
- The network ACLs allow inbound from `0.0.0.0/0` on the ephemeral ports (stateless
  return traffic) and, on public subnets, 80/443 for internet-facing load balancers.
  This is the documented exception to the "no inbound /0" rule; see `network-acls.tf`.
- The database NACL's VPC-CIDR egress rule 100 (the reply leg back to an
  application-tier client) spans `1024-65535`, not the narrower `32768-65535`
  used elsewhere: AWS Lambda functions attached to the VPC (e.g.
  redis-auth-rotation) source outbound connections from their Hyperplane ENI
  across the full documented range, so the database subnet's stateless reply
  needs the wider window. Ingress rule 140 stays at `32768-65535` — it covers
  replies to connections the database subnet itself initiates outbound, not a
  Lambda's inbound request, whose destination port is the fixed service port
  (rules 100-130), not an ephemeral one. VPC-internal only, so it does not
  touch the no-inbound-/0 rule.
- The database-subnet fix above does not cover a VPC-attached Lambda's calls
  to *AWS APIs themselves* (e.g. redis-auth-rotation's Secrets Manager and
  ElastiCache calls): those go out the NAT gateway to a public endpoint, and
  the reply comes back to the Lambda's own ephemeral source port, which for
  a Hyperplane ENI can be anywhere in 1024-65535 — but the private NACL's
  only `/0` ingress rule (110) admits just `32768-65535`. Widening that `/0`
  rule would need explicit owner sign-off (it is a real inbound-`/0` change,
  not the VPC-internal one above), so instead the fix is `enable_vpc_endpoints`
  / `vpc_endpoints`: an Interface endpoint's reply comes from an address
  inside the VPC CIDR, which the existing VPC-CIDR NACL rules already admit,
  so no widening is needed at all. `microservices/vpc` enables `secretsmanager`
  and `elasticache` for this reason.
- `stacks/mixins/stage/*` set stage defaults on the abstract `vpc/defaults`, never on a
  bare `vpc` key (which would create a real, stray instance). An instance's own values
  win over the stage defaults.

## Usage

```
atmos terraform plan vpc/main -s fnx-dev-testenv-01
atmos terraform plan vpc/services -s fnx-prod-production
```

## Tests

`tests/*.tftest.hcl` run against a mock provider:
`terraform init -backend=false && terraform test`.
