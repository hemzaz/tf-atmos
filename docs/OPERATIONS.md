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
atmos workflow hot-deploy -f deploy-application -s <stack>   # Cognito, Lambda and API Gateway only
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
plans it like anything else. The eks component used it for five renames to
snake_case for `terraform_naming_convention` (those blocks went away with the
one-cluster-per-instance restructure, which changed every eks address while
nothing had been applied, so there was no state to move):

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
  `securitygroup` upgrade does not move them: it replaces every group
  (`name` becomes `name_prefix`), so the new group is created with its rules
  as resources while the old one keeps its inline rules until it is destroyed.
  Its consumers live in other components, which makes that a three-apply
  rollout -- this component, then its consumers, then this component again --
  documented under "Replacing a group" in
  [the component README](../components/terraform/securitygroup/README.md#replacing-a-group).
  The reverse has the same shape: the provider documents that a
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
STACK=<stack> atmos workflow harden -f security-hardening        # deploy guardduty/securityhub, EBS/S3 defaults
STACK=<stack> atmos workflow harden-iam -f security-hardening    # account password policy
atmos workflow check -f compliance-check -s <stack>              # CIS, FSBP, PCI DSS, ... from Security Hub
atmos workflow report -f compliance-check -s <stack>             # writes compliance-report.md
```

`harden`/`harden-iam` ask before changing anything; declining runs report-only. GuardDuty and
Security Hub are owned by the `guardduty/main` and `securityhub/main` components in every stack;
`harden` plans them and prints the plans before its confirm prompt, then applies exactly those
planfiles with `atmos terraform deploy --from-plan` (never with aws CLI create calls, which would
collide with Terraform) and reports their status. `security-monitoring/main` routes their findings
to SNS and reads their IDs with `!terraform.state`.

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

## eks and ec2: one cluster or instance per component instance (2026-09-24)

`eks` and `ec2` follow the Cloud Posse model: each component instance is one
cluster (`eks/main`, `eks/data`) or one instance (`ec2/bastion`,
`ec2/app-server`). The `clusters` and `instances` maps and the map outputs are
gone; instances set `name` and top-level variables, and readers use the Cloud
Posse scalar outputs (`eks_cluster_id`, `eks_cluster_endpoint`,
`eks_cluster_certificate_authority_data`, `eks_cluster_identity_oidc_issuer`,
`eks_cluster_identity_oidc_issuer_arn`; ec2 `ssh_key_pair`, `security_group_id`).
See each component's README.

Every name is `<Environment>-<name>`, and `name` may not repeat the
Environment, so no name doubles it any more:

| Stack | Clusters | ESO roles | EC2 instances |
|---|---|---|---|
| fnx-dev-testenv-01 | `testenv-01-main`, `testenv-01-data` | `testenv-01-{main,data}-external-secrets-role` | `testenv-01-bastion`, `testenv-01-app-server` |
| fnx-staging-staging-01 | `staging-01-main`, `staging-01-data` | `staging-01-{main,data}-external-secrets-role` | `staging-01-bastion`, `staging-01-app-server` |
| fnx-prod-production | `production-main`, `production-data` (were `production-production-*`) | `production-{main,data}-external-secrets-role` | `production-bastion` (was `production-production-bastion`) |

Nothing from these components had been applied (CD's AWS jobs were always
skipped), so the change ships as plain code with no state migration. Were
state to exist, every eks and ec2 address changed and the prod names changed:
a plan would replace the resources, which is the signal to stop.

**SSH keys: nothing to create by hand.** No bastion names an existing key
pair. The component generates one ED25519 key per instance, the key pair
`<Environment>-<name>-ec2-ssh-key`, and stores its private key in Secrets
Manager at `ssh-key/<Environment>/<name>`, encrypted with the stack's
`kms/main` key: `testenv-01-bastion-ec2-ssh-key` / `ssh-key/testenv-01/bastion`,
`staging-01-bastion-ec2-ssh-key` / `ssh-key/staging-01/bastion`,
`production-bastion-ec2-ssh-key` / `ssh-key/production/bastion`. Each
`ec2/app-server` launches with its bastion's key
(`!terraform.state ec2/bastion .ssh_key_pair`) and never generates its own
(`create_ssh_keys: false`).

Apply order within a stack: `kms/main`, then `ec2/bastion`, then
`ec2/app-server`.

To fetch a private key, read `private_key_openssh`: for an ED25519 key,
`private_key_pem` is PKCS#8, which OpenSSH rejects ("Load key: invalid
format").

```bash
aws secretsmanager get-secret-value --secret-id ssh-key/<Environment>/bastion \
  --query SecretString --output text | jq -r .private_key_openssh > bastion.key
chmod 600 bastion.key
# or: scripts/certificates/export-ssh-key.sh -r eu-west-2 -s ssh-key/<Environment>/bastion -o bastion.key
```

The private key is also in the component's Terraform state (in
`fnx-terraform-state`), as it was on master: whoever can read that state can
reach the bastion.

**Egress.** The repo's 0.0.0.0/0 rule restricts inbound traffic only
(ingress, EKS public access). Instances may reach any address outside; the ec2
default egress is Cloud Posse's, all outbound traffic.

**Kubernetes 1.36.** Every stack pins `eks_kubernetes_version: "1.36"`, and
node groups default to `AL2023_x86_64_STANDARD` (Cloud Posse's
aws-eks-node-group default). AWS publishes no Amazon Linux 2 EKS AMIs for 1.33
and later, so the eks component rejects an `AL2_*` `ami_type` on such a
cluster.
