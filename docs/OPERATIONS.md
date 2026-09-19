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
