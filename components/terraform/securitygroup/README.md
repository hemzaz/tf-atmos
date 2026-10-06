# securitygroup

One security group per `security_groups` entry, with each rule a separate
`aws_security_group_rule`, plus a plan-time permissive-ingress audit (`audit.tf`). Ports Cloud
Posse `terraform-aws-security-group`'s model: rule keys and `normalize.tf`,
`preserve_security_group_id`, `allow_all_egress`, `name_prefix` naming. Like that module, it
creates no monitoring: security group change alerting is account-level and lives in
`security-monitoring`.

## Wiring

- Instance: `securitygroup/app` in `fnx-ue1-local-sandbox` only; reads `vpc/main .vpc_id`.
- The `web-application`, `batch-processing` and `microservices-platform` catalog templates and the
  `templates/stacks/{minimal,full,microservices}-stack.yaml` stack templates configure it;
  consumers (ALB, ECS, RDS, ElastiCache, Batch) read `.security_group_ids.<key>`.

## Notes

- A rule's source can be the key of a sibling group in the same map. Give every rule an explicit
  `key` and a single source: unkeyed rules are positional, so removing one renumbers the rest.
- `preserve_security_group_id = false` (default): any rule change replaces the whole group; see
  [Replacing a group](#replacing-a-group).
- `preserve_security_group_id = true`: the group is kept and changed rules are destroyed before
  being recreated (briefly absent). Moving a permission between rule instances in one apply
  fails with `InvalidPermission.Duplicate`; remove it in one apply, add it in the next. The
  sandbox and the `web-application` and `batch-processing` templates set `true`.
- `allow_all_egress` defaults to `true` (Cloud Posse). Set it `false` on a group that already has
  its own all-outbound rule, or apply fails with a duplicate. Overlapping CIDRs across two rules
  on the same ports fail the same way.
- The group has no inline egress, so the provider removes AWS's default allow-all egress rule. With
  `allow_all_egress: false` and no `egress_rules`, the group can send nothing.
- `enforce_no_public_ingress` defaults to `true`: apply fails on ingress from `0.0.0.0/0` or `::/0`.
  Egress is not checked.
- Validation rejects a group `name` (names are generated), protocol aliases such as `"6"` or
  `"all"`, a rule sourcing its own group's key (use `self`), and rules without a source.

## Replacing a group

A group is replaced on any rule change under `preserve_security_group_id = false`, and on a
`description` or `vpc_id` change under either setting. Consumers in other components keep the old
group attached, so the rollout takes three applies:

1. Apply this component. The new group is created; destroying the old one fails with
   `DependencyViolation` (expected). The old group's rules are already revoked at this point.
2. Apply every consumer straight away, so each moves to the new `security_group_ids` value.
3. Re-apply this component to destroy the old group.
