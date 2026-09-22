# securitygroup

Creates one `aws_security_group` per entry in the `security_groups` map and one
`aws_security_group_rule` per rule source (`main.tf`, normalized in
`normalize.tf`), plus optional CloudWatch logging/alarms on security-group
change events and a permissive-ingress detector with a `terraform_data`
precondition that can block apply (`audit.tf`).

Rules are separate resources, not inline `ingress`/`egress` blocks, for the two
reasons cloudposse/terraform-aws-security-group gives ("Setting
`inline_rules_enabled` is not recommended and NOT SUPPORTED"): an inline block
cannot reference `aws_security_group.this`, so a rule sourced from a sibling
group in the same map is unexpressible; and inline blocks are authoritative for
the whole group, so changing one rule updates the group itself.

## Deployed

`securitygroup/app` in `fnx-local-sandbox` only
(`stacks/orgs/fnx/local/eu-west-2/sandbox.yaml`) — one group, one ingress rule,
one egress rule, with `enforce_no_public_ingress: true` so the guard is
exercised. Floci does not implement `PutMetricFilter`, so that instance sets
`enable_security_group_logging`/`enable_security_group_alarms` to `false`.

None of the three real stacks (fnx-dev-testenv-01, fnx-staging-staging-01,
fnx-prod-production) deploy it. `stacks/catalog/templates/web-application.yaml`
and `batch-processing.yaml` configure it, but neither template is imported by a
stack today.

## Inputs / outputs

| Key | Notes |
|---|---|
| `vpc_id` (required) | — |
| `security_groups` (map, default `{}`) | typed `map(object(...))`; keys name the groups and are how rules refer to each other |
| `tags` | required; must include a non-empty `Environment` (validated), used in the group names `${Environment}-${key}-sg` |
| `enforce_no_public_ingress` | when `true`, apply fails if any rule allows ingress from `0.0.0.0/0` or `::/0` |
| `log_retention_days` | must be a valid CloudWatch retention value (validated) |
| out: `security_group_ids`, `security_group_arns`, `security_group_vpc_id` | maps keyed by the `security_groups` key |
| out: `security_group_names` | the generated group names; the group is created from a `name_prefix`, so the full name is only known after apply |
| out: `security_group_rule_ids` | keyed by normalized rule key, e.g. `app/ingress[0]#cidr` — read this when a rule is unexpectedly replaced |
| out: `common_rule_templates`, `security_validation_warnings` | reference templates and the permissive-rule report |

Each rule takes `from_port`, `to_port`, `protocol` and at least one source:
`cidr_blocks`, `ipv6_cidr_blocks`, `prefix_list_ids`, `security_groups` (a
list), `source_security_group_id` (the singular spelling), or `self: true`. A
security-group source may be either an `sg-...` id or **the key of another group
in the same map**, which is resolved to that group's id after it is created:

```yaml
security_groups:
  alb:
    ingress_rules:
      - { from_port: 443, to_port: 443, protocol: tcp, cidr_blocks: ["0.0.0.0/0"] }
  application:
    ingress_rules:
      - from_port: 8080
        to_port: 8080
        protocol: tcp
        source_security_group_id: "alb"     # sibling key, not an id
```

Rules are keyed by their position in the list. Set `key` on a rule to give it a
stable identity, otherwise deleting the second of four rules renumbers — and so
replaces — the two after it.

## Dependencies & gotchas

- The only `dependencies.components` entry is the sandbox instance's `vpc/main`.
- `tags` without a non-empty `Environment` fails validation before any plan.
- `enforce_no_public_ingress = true` is a hard gate via a `terraform_data`
  precondition, not a warning. It now covers `::/0` as well as `0.0.0.0/0`.
- Four `validation` blocks on `var.security_groups` reject, before any provider
  is configured: a map key shaped like `sg-...`; a rule source that is neither a
  sibling key nor an `sg-...` id; a rule with no source at all; and an IPv4
  prefix in `ipv6_cidr_blocks` (or the reverse).
- The groups are created with `name_prefix`, not `name`. They are
  `create_before_destroy`, and two security groups in a VPC cannot share a name,
  so a fixed name would fail replacement with `InvalidGroup.Duplicate`.
  Cloudposse does the same. The readable name is the `Name` tag.
- The rules use `aws_security_group_rule`, the same resource Cloudposse uses. It
  takes the CIDR and prefix-list sources as lists (one resource rather than one
  per prefix) and accepts `protocol = "-1"` with `from_port`/`to_port` `0`, which
  `aws_vpc_security_group_ingress_rule` returns as `-1` and then diffs against
  forever. It is marked deprecated in the provider documentation, with no
  announced removal.
- The group carries no inline egress, so the provider removes AWS's default
  allow-all egress rule. `egress_rules` is therefore the whole of a group's
  egress — a group with none can send nothing.

## Migration from the inline-rule version

Nothing in this repo needs migrating: the only instance is in the ephemeral
`fnx-local-sandbox`, which is created and destroyed by
`atmos workflow sandbox -f sandbox`. The note below is for any state created
outside it.

`moved {}` cannot help. Inline `ingress`/`egress` are *attributes* of
`aws_security_group`, not separate state objects, so there is nothing for
`moved` or `terraform state mv` to address — which is why Cloudposse ships no
`moved` blocks for this either. Applying the new version straight over old state
can fail with `InvalidPermission.Duplicate`, because the new rule resources may
be created before the inline rules are revoked.

The upgrade is two applies:

1. On the **old** version, set every group's `ingress_rules` and `egress_rules`
   to `[]` and apply. That revokes the inline rules while the groups stay.
2. Upgrade the component, restore the rules, and apply.

The second apply also **replaces every group**, because of the `name` →
`name_prefix` change. Replacement is create-before-destroy, so the new group
exists first, but the old one cannot be destroyed while an ENI still references
it: everything attached to it — instances, load balancers, RDS, anything reading
`security_group_ids` — has to be updated in the same run, or the destroy fails
with `DependencyViolation`.

## Usage

```
atmos terraform plan securitygroup/app -s fnx-local-sandbox
```
