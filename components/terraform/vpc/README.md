# vpc

VPC with public, private and database subnets (one per AZ), internet gateway, NAT gateway(s)
(`single` or `one_per_az`), route tables, network ACLs, optional VPC endpoints, VPN/Transit
Gateway attachment and RAM sharing, and VPC Flow Logs to CloudWatch with security alarms. Input
names follow Cloud Posse `aws-vpc` where an input maps one to one.

## Wiring

- Reads: `kms/main .key_arn` as `flow_logs_kms_key_arn` (set by `vpc/defaults`).
- Used by: `dns` (`network/main`), `ec2`, `eks`, `eks-addons`, `elasticache`, `lambda`, `rds`,
  `network/vpc-peering` and `securitygroup`, via `vpc_id`, `private_subnet_ids`,
  `database_subnet_ids` and `private_route_table_ids`.

## Notes

- Instances: `vpc/main` and `vpc/services` in the three AWS stacks, `vpc/main` also in both local
  stacks. Stage mixins set defaults on abstract `vpc/defaults`, never on a bare `vpc` key (that
  would create a stray real instance).
- `tags` must carry a non-empty `Environment`: it is used in resource names.
- Empty `flow_logs_kms_key_arn` makes the component create its own key; a caller's key needs a
  `logs.<region>.amazonaws.com` statement scoped by `kms:EncryptionContext:aws:logs:arn`.
- `map_public_ip_on_launch` defaults to `false` (Cloud Posse defaults to `true`).
- `manage_default_security_group` (default `true`) strips every rule from the AWS default SG.
- There is no ElastiCache subnet tier; caches use `private_subnet_ids`.
- NACLs allow inbound `0.0.0.0/0` only on ephemeral ports and, on public subnets, 80/443: the
  documented exception to the no-inbound-/0 rule (`network-acls.tf`). The private NACL's `/0`
  return rule admits only 32768-65535, so a VPC-attached Lambda calling AWS APIs through NAT can
  lose replies; enable `vpc_endpoints` for those services instead (as `microservices/vpc` does
  for `secretsmanager` and `elasticache`). `s3`/`dynamodb` become Gateway endpoints, everything
  else Interface endpoints.
- The private NACL admits only this VPC's CIDR (plus `/0` return traffic), so a peered VPC's CIDR
  goes in `private_network_acl_peer_cidr_blocks` on both sides (all traffic in and out, rules
  200+, at most 15: with the 5 private egress rules that is the default NACL quota of 20). The stacks set each from the other vpc's CIDR in the stack's `settings.network.vpc_cidrs`,
  which also sets `ipv4_primary_cidr_block`; `!terraform.state` would make the two vpcs read each
  other, a cycle.
