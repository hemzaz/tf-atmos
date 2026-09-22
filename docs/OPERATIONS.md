# Operations Guide

Day-2 tasks for the three stacks (`fnx-dev-testenv-01`, `fnx-staging-staging-01`,
`fnx-prod-production`). Everything here is an Atmos command or workflow; run
`atmos list workflows` for the full list. First-time deployment is in the
[Deployment Guide](./DEPLOYMENT.md).

Workflows that take `-s <stack>` target that stack. Workflows whose usage shows `STACK=<stack>`
read it from that environment variable (or prompt for it).

## Routine checks

| Check | How | Automated |
|-------|-----|-----------|
| Drift | `atmos workflow drift-detection -f drift-detection -s <stack>` | Hourly, `drift-detection.yml` (read-only plan role; drift fails the job) |
| Security scan | `atmos workflow security-scan -f lint` (fails on HIGH/CRITICAL) or `security-scan-report -f lint` (report only); SARIF lands in `reports/` | Nightly `security-scan.yml`; every PR |
| Lint and validation | `atmos workflow lint -f lint` (fmt, yamllint, Trivy, TFLint) and `atmos workflow validate-all -f validate-enhanced`. Run `atmos workflow tflint-init -f lint` once first (installs TFLint + rulesets from `.tflint.hcl`) | Every PR |
| Scan baselines | `atmos workflow security-baseline -f lint` rewrites `.trivyignore.yaml`/`.checkov.baseline` from current findings. Regenerate after fixing findings, never to force a failing PR green; review the diff | No |
| DR readiness | `STACK=<stack> atmos workflow dr-status -f disaster-recovery` | Manual `disaster-recovery.yml` |
| Security Hub findings | `atmos workflow security-audit -f security-hardening -s <stack>` | No |

Drift remediation, as the workflow prints it: expected change made outside Terraform → codify it in
the stack config, then `atmos terraform deploy <component> -s <stack>`; unexpected change →
re-apply with the same command; resource created outside Terraform →
`atmos workflow import -f import -s <stack>`.

## Changing infrastructure

Normal path: a pull request. CI plans every affected component and comments on the PR; after merge,
CD deploys each affected stack in turn (dev, staging, prod), gated by that stack's GitHub
Environment. Local equivalents:

```bash
atmos terraform plan <component> -s <stack>
atmos terraform deploy <component> -s <stack>
atmos workflow plan -f plan-environment -s <stack>       # every component, no apply
atmos workflow apply -f apply-environment -s <stack>     # every component, one confirmation
atmos workflow deploy-app -f deploy-application -s <stack>   # application layer on an existing foundation
atmos workflow hot-deploy -f deploy-application -s <stack>   # Lambda and API Gateway only
```

## Moving resources in state

A change that renames a resource, moves it into or out of a module, or switches
it between `count` and `for_each` does not change any infrastructure — but
Terraform sees a new address and plans to destroy the old resource and create
the new one. The plan is the only warning. Read every plan for `to destroy` and
`must be replaced` before applying, especially on a refactor that was supposed
to be cosmetic.

### The default: `moved {}` in the component

Put a `moved` block in the component, next to the resource, with a one-line
reason. It is code: it is reviewed in the PR, it applies to every stack, and CI
plans it like anything else. `components/terraform/eks/main.tf` is the
precedent — five renames to snake_case for `terraform_naming_convention`:

```hcl
# Renamed to snake_case (tflint terraform_naming_convention); keeps existing state.
moved {
  from = aws_iam_role_policy_attachment.cluster_AmazonEKSClusterPolicy
  to   = aws_iam_role_policy_attachment.cluster_eks_cluster_policy
}
```

A `moved` block whose `from` address is absent from state is a no-op, so it is
safe to keep after every stack has applied it, and safe to add for stacks that
never had the old address. Leave them in for at least one full deploy cycle
across dev, staging and prod; they can be deleted once `deployed/<stack>` has
moved past the change in all three.

`moved` covers: renaming a resource, moving one between modules, changing an
index (`count` to `for_each`, or a `for_each` key), and renaming a module call.

### `terraform state mv` is the fallback, not the tool

```bash
atmos terraform state mv <component> -s <stack> '<old address>' '<new address>'
```

Prefer `moved` wherever it applies. `state mv` is a manual act that has to be
repeated for every stack, leaves no trace in the repository for the next
reader, and cannot be reviewed. Use it only when the move cannot be expressed
in configuration — for example when state has to be split across two components
— and record what was run in the PR description.

### What `moved` cannot express

`moved` relabels one state object as another. It cannot help when there is no
old object to relabel:

- **An attribute becoming a resource.** Inline `ingress`/`egress` blocks are
  attributes of `aws_security_group`, not separate state objects, so promoting
  them to `aws_security_group_rule` resources has nothing to move from. The
  `securitygroup` README documents the two-apply procedure this needs: revoke
  the inline rules on the old version first, then upgrade and re-create them as
  resources. The reverse has the same shape: the provider documents that a
  group cannot carry inline rules and `aws_security_group_rule` resources at
  once — the two overwrite each other — so the rules have to be removed before
  the inline blocks are added. Any `dynamic` block promoted to a real resource
  hits this.
- **A replacement the provider forces.** Changing `name` to `name_prefix`, or
  any other `ForceNew` attribute, replaces the resource whatever its address
  is. That is not a state problem and no state operation avoids it; the
  question to answer in the PR is what else depends on the identifier that is
  about to change.
- **A different root module.** `network/main` is a `dns` instance, not a
  `network` one (`metadata.component` decides). State written by one module does
  not match another module's addresses, so switching an instance's
  `metadata.component` means importing, not moving — see
  [Importing existing resources](#importing-existing-resources).

### Verifying a move

```bash
atmos terraform plan <component> -s <stack>     # expect: 0 to add, 0 to change, 0 to destroy
```

A move that is complete plans as a no-op. If the plan still wants to destroy and
re-create, an address is still unaccounted for. Check it in every stack that has
state for the component, not just the first — `moved` applies everywhere, but a
`for_each` key that differs per stack does not.

Backend relocation (a different bucket or key, rather than a different address)
is a separate procedure: see
[Migrating existing state](./DEPLOYMENT.md#migrating-existing-state).

## State locks

The S3 backend uses Terraform's native lockfiles (`use_lockfile: true`) — a lock is a
`<state key>.tflock` object next to the state; there is no DynamoDB table.

```bash
STACK=<stack> atmos workflow list-locks -f state-operations   # lockfiles and their age
atmos workflow force-unlock -f state-operations -s <stack>    # release one component's lock
```

Only force-unlock when no plan or apply is running for that component, locally or in CI.

## State recovery

The state bucket is versioned.

```bash
atmos describe component <component> -s <stack>   # .backend.workspace_key_prefix and .workspace
STACK=<stack> COMPONENT_PREFIX=<root-module>/ atmos workflow recover-state -f disaster-recovery
```

`recover-state` prints the `aws s3api copy-object` command that makes an older version current.
Run `atmos terraform plan <component> -s <stack>` afterwards before applying anything.

## Disaster recovery

Guided runbooks in `workflows/disaster-recovery.yaml`.

```bash
STACK=<stack> atmos workflow dr-status -f disaster-recovery          # readiness report
STACK=<stack> atmos workflow recover-database -f disaster-recovery   # RDS snapshots, PITR windows
STACK=<stack> atmos workflow dr-failover -f disaster-recovery        # failover to the DR region
STACK=<stack> atmos workflow dr-failback -f disaster-recovery        # back to the primary region
```

Failover and failback are interactive and never run from CI; `disaster-recovery.yml` only runs the
read-only checks.

## Security and compliance

```bash
atmos workflow security-audit -f security-hardening -s <stack>   # Security Hub findings mapped to components
STACK=<stack> atmos workflow harden -f security-hardening        # GuardDuty, Security Hub, EBS/S3 defaults
STACK=<stack> atmos workflow harden-iam -f security-hardening    # account password policy
atmos workflow check -f compliance-check -s <stack>              # CIS, FSBP, PCI DSS, ... from Security Hub
atmos workflow report -f compliance-check -s <stack>             # writes compliance-report.md
```

`harden`/`harden-iam` ask before changing anything; declining runs report-only. In production,
`guardduty/main` and `securityhub/main` are disabled stack instances, so `harden` manages those
services instead of Terraform.

## Certificate rotation

ACM certificates are Terraform-managed (`acm/main`, `acm/services`) with DNS validation. For a
certificate kept in Secrets Manager and synced into Kubernetes:

```bash
atmos workflow rotate -f rotate-certificate   # prompts for secret name, namespace, optional ACM ARN
```

## Importing existing resources

```bash
atmos workflow import -f import -s <stack>
```

Prompts for the component instance, Terraform resource address and cloud resource ID, imports after
confirmation, then shows the follow-up plan so the stack config can be reconciled.

## Destroying a stack

```bash
atmos workflow destroy -f destroy-environment   # every component, reverse dependency order
atmos workflow destroy -f destroy-backend       # the state bucket and every state file in it
```

Both prompt for the stack name and require it typed again to confirm; do not pass `-s`. Destroying
the backend is irreversible and removes the state of every stack that shares the bucket.
