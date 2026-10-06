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
- `name` (Cloud Posse's context name; `vpc/defaults` sets the instance's last path segment, `main`
  for `vpc/main`) goes into the account- and region-unique names: the flow-logs KMS alias, IAM role
  and policy, alarms, metric namespace (`VPC/FlowLogs/<Environment>-<name>`) and archive bucket. So
  `vpc/main` and `vpc/services` of one stack create distinct ones (`check-lane-names.py` fails two
  instances of a component in one stack that set the same name inputs). Names scoped to the VPC or
  its log group keep `<Environment>` alone.
- Set exactly one of `availability_zone_ids` and `availability_zones`. The AWS stacks use IDs
  (`use1-az1`, `use1-az2`, `use1-az4`): in us-east-1 each account maps the names a/b/c to its own
  physical zones, and EKS rejects a cluster subnet in `use1-az3`, so a name could land there.
  The local (emulator) stacks keep names.
- Empty `flow_logs_kms_key_arn` makes the component create its own key; a caller's key needs a
  `logs.<region>.amazonaws.com` statement scoped by `kms:EncryptionContext:aws:logs:arn`.
- `flow_logs_s3_backup` adds a second flow log into an archive bucket (bucket policy for
  `delivery.logs.amazonaws.com`, as Cloud Posse's `vpc-flow-logs-s3-bucket`). A caller
  `flow_logs_kms_key_arn` must grant that service `kms:GenerateDataKey*`: kms/main does through
  `allow_log_delivery` (on in `kms/defaults`).
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
  200+, at most 15: with the 5 private egress rules that is the default NACL quota of 20). The
  stacks set each from the other vpc's CIDR in the stack's `settings.network.vpc_cidrs`, which
  also sets `ipv4_primary_cidr_block`; `!terraform.state` would make the two vpcs read each
  other, a cycle.
