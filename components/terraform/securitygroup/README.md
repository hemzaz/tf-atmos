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
exercised, and `preserve_security_group_id: true`. Floci does not implement `PutMetricFilter`, so that instance sets
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
| `security_groups.<key>.preserve_security_group_id` | default `false`; see [Rule changes](#rule-changes-preserve_security_group_id) |
| `security_groups.<key>.name` | rejected by validation: names are generated, see below |
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

Rules are keyed the way Cloudposse's `normalize.tf` keys them: the rule's `key`
if it has one, otherwise its position in its list
(`coalesce(rule.key, "${type}[${i}]")`), prefixed with the group's map key. Each
rule is then split per source kind with Cloudposse's rule-matrix suffixes:
`#cidr` (CIDRs and prefix lists), `#self`, and `#sg#<i>` per source group, with
`source_security_group_id` appended to the `security_groups` list. So
`app/ingress[0]#cidr`, `application/ingress[0]#sg#0`, or `app/https#cidr` for a
rule with `key: https`. A `key` must be unique within its group, across ingress
and egress. A repeat is Terraform's own "Duplicate object key" error, as in
Cloudposse.

Removing a rule from the middle of a list renumbers every rule after it. How
that plays out depends on the setting below:

- `preserve_security_group_id = false`: the renumbered rules change the
  `random_id` keepers, so the group is replaced and every rule is created on the
  new, empty group. Nothing is authorized twice. Cloudposse: "If you are using
  'create before destroy' behavior for the security group and security group
  rules, then ... keys do not matter".
- `preserve_security_group_id = true`: each later index is replaced, destroy
  before create, with its successor's content, and the last index is destroyed.
  Those rules are briefly absent. This is the "ripple effect" Cloudposse's README
  describes. It is worse than a gap: Terraform orders destroy-then-create
  *within* one instance, not between two. A review of this component saw the
  destroy of one instance and the create of another start 2 ms apart. A rule
  that moves from `[1]` to `[0]` can be authorized at `[0]` while `[1]` still
  holds it, and AWS rejects that with `InvalidPermission.Duplicate`.

Cloudposse's guidance for when group ids must be preserved: "You can avoid this
for the most part by providing the optional keys, and limiting each rule to a
single source or destination." Every rule in both catalog templates and the
sandbox stack has an explicit `key` and a single source, and every group there
sets `preserve_security_group_id: true`. Do the same for any group that
preserves its id.

**Adding or renaming a `key` on an existing rule** under
`preserve_security_group_id = true` moves the rule's permission to a new
instance, which is exactly the race above. Use two applies:

1. Remove the rule and apply. The old instance is revoked.
2. Add it back with its new `key` and apply. The new instance is authorized.

The rule is absent between the two applies. Under `false` a key change is just
another rule change: a new group is created, and one apply is enough.

**Known limit: overlapping CIDRs.** Two rules on the same group, direction,
protocol and ports whose CIDR lists overlap (`[a, b]` and `[b, c]`) authorize
`b` twice. Plan passes and apply fails with `InvalidPermission.Duplicate`.
Cloudposse has no guard for this either. Keep each CIDR in exactly one rule per
protocol and port range.

### Rule changes: `preserve_security_group_id`

This is Cloudposse's model (`main.tf`, and
[issue #34](https://github.com/cloudposse/terraform-aws-security-group/issues/34)),
set per group. Almost every `aws_security_group_rule` attribute forces
replacement. Creating the replacement rule before destroying the original, on
the same group, authorizes permissions that still exist, and AWS rejects the
whole call with `InvalidPermission.Duplicate`. Destroying first leaves a gap.
The two settings choose which cost to pay:

| | `false` (default) | `true` |
|---|---|---|
| on any rule change | a **new group** is created with all the rules; the old one is destroyed | the group is kept; changed rules are revoked, then re-authorized |
| how | a `random_id` whose keepers are the group's normalized rules feeds the `name_prefix`; rules are `create_before_destroy` (`aws_security_group_rule.keyed`) | fixed `name_prefix`, no `random_id`; rules are destroy-before-create (`aws_security_group_rule.dbc`) |
| traffic | the new group has every rule before anything moves to it, but the old group's rules are revoked in the same apply: with consumers in other components (all of them, here) the whole group is empty until they move. See [Replacing a group](#replacing-a-group) | a changed rule is briefly absent; unchanged rules are untouched |
| consumers | must move to the new id: see [Replacing a group](#replacing-a-group) | unaffected |

A change to `description` or `vpc_id` replaces the group under either setting,
and flipping the setting itself changes the `name_prefix`, so it replaces the
group too. Rule descriptions are part of the keepers, so under `false` a
description-only edit also creates a new group (as in Cloudposse).

Use `true` for a group whose id is referenced where Terraform cannot move it: a
rule in another component's group, a hard-coded id, a resource that cannot
change its security groups in place.

Cloudposse's `null_resource.sync_rules_and_sg_lifecycles` is ported, one per
`false` group: it is triggered by the group's id, depends on the
`create_before_destroy` rules, and is itself `create_before_destroy`. When a
group is replaced, the new group's rules therefore all exist before the deposed
rules are destroyed. The other half of its purpose, holding the old rules until
consumers have moved to the new group, needs the consumers in the same plan, and
every consumer here is in another component. That is why the gap described
under [Replacing a group](#replacing-a-group) remains.

## Dependencies & gotchas

- The only `dependencies.components` entry is the sandbox instance's `vpc/main`.
- `tags` without a non-empty `Environment` fails validation before any plan.
- `enforce_no_public_ingress = true` is a hard gate via a `terraform_data`
  precondition, not a warning. It now covers `::/0` as well as `0.0.0.0/0`.
- Six `validation` blocks on `var.security_groups` reject, before any provider
  is configured: a `name` on a group; a map key shaped like `sg-...`; a rule
  source that is neither a sibling key nor an `sg-...` id; a rule with no source
  at all; an IPv4 prefix in `ipv6_cidr_blocks` (or the reverse); and a protocol
  alias (`"6"`, `"17"`, `"1"`, `"58"`, `"all"`, upper case) in place of `tcp`,
  `udp`, `icmp`, `icmpv6`, `-1`. The aliases name the same AWS permission, so a
  mix fails at apply as a duplicate. Cloudposse passes `protocol` through
  unnormalized, so this rejects the aliases rather than rewriting them.
- The groups are created with `name_prefix`, not `name`:
  `<Environment>-<key>-sg-<random_id>-` (or `<Environment>-<key>-sg-` with
  `preserve_security_group_id`), and AWS appends a unique suffix. They are
  `create_before_destroy`, and two security groups in a VPC cannot share a name,
  so a fixed name would fail replacement with `InvalidGroup.Duplicate`.
  Cloudposse does the same. The readable name is the `Name` tag. A per-group
  `name` was accepted and silently ignored by an earlier revision; it is now a
  validation error rather than dropped from the type, because Terraform drops
  an attribute that is missing from an object type without saying so.
- The rules use `aws_security_group_rule`, the same resource Cloudposse uses. It
  takes the CIDR and prefix-list sources as lists (one resource rather than one
  per prefix) and accepts `protocol = "-1"` with `from_port`/`to_port` `0`, which
  `aws_vpc_security_group_ingress_rule` returns as `-1` and then diffs against
  forever. It is marked deprecated in the provider documentation, with no
  announced removal.
- The group carries no inline egress, so the provider removes AWS's default
  allow-all egress rule. `egress_rules` is therefore the whole of a group's
  egress — a group with none can send nothing.

## Replacing a group

A group is replaced on every rule change when `preserve_security_group_id` is
`false`, on a `description` or `vpc_id` change under either setting, and once
for every group on the upgrade below. The consumers (ALB, ECS service, RDS,
ElastiCache, Batch) live in other components and read the id through
`!terraform.state <this instance> .security_group_ids.<key>`. Nothing in this
component's plan can move them, so the old group is still attached to their
ENIs when this apply tries to destroy it, and AWS refuses with
`DependencyViolation`. The rollout is three applies:

1. **Apply this component.** The new group is created with all its rules. The
   destroy of the old group fails with `DependencyViolation` after the
   provider's delete timeout (15 minutes by default). The apply exits non-zero;
   that is expected. The old group stays in state as a deposed object, still
   attached to the consumers. `security_group_ids` already holds the new id.
2. **Apply every consumer.** Each reads the new id and swaps its ENIs to it.
3. **Re-apply this component.** Nothing references the old group any more, so
   its destroy succeeds.

Step 1 only fails when something outside this component still uses the group.
In the sandbox nothing does, and a single apply completes.

**Traffic between steps 1 and 2.** The old group's rules are separate
resources that depend on it, so step 1 revokes them *before* it attempts the
group's destroy, and a revoke does not wait for the ENIs. The consumers keep the
old group, now empty, until step 2 moves them: that window is a gap for every
rule on the group, not just the changed one. Run step 2 straight after step 1.
This is the cost of the consumers living in other components; Cloudposse's
"no interruption" ordering holds only when the consumers are in the same plan.
The two cases without the gap: the inline-rule upgrade below (the old group's
rules are inline, so nothing revokes them), and `preserve_security_group_id =
true`, where a rule change never replaces the group. For a group whose
consumers are in other components, which is every group in the catalog
templates, `preserve_security_group_id = true` keeps a rule change down to the
changed rule being briefly absent. Both catalog templates and the sandbox
instance set it on every group; the component default stays `false`, which is
Cloudposse's default.

## Migration from the inline-rule version

Nothing in this repo needs migrating: the only instance is in the ephemeral
`fnx-local-sandbox`, which is created and destroyed by
`atmos workflow sandbox -f sandbox`. The note below is for any state created
outside it.

`moved {}` cannot help. Inline `ingress`/`egress` are *attributes* of
`aws_security_group`, not separate state objects, so there is nothing for
`moved` or `terraform state mv` to address — which is why Cloudposse ships no
`moved` blocks for this either.

The upgrade replaces **every** group: `name` → `name_prefix` forces a new
resource under either `preserve_security_group_id` setting. The new rule
resources are created on the new group, not the old one, so they cannot collide
with the old group's inline rules. The old group keeps its inline rules until it
is destroyed. Upgrade the component and follow [Replacing a group](#replacing-a-group):
apply this component, apply the consumers, re-apply this component.

An earlier revision of this README said to first apply the old version with
every rule list set to `[]`. Do not. It revokes every rule from groups that
consumers are still attached to, which is an outage, and it prevents nothing:
the new rules never land on the old group.

## Usage

```
atmos terraform plan securitygroup/app -s fnx-local-sandbox
```
