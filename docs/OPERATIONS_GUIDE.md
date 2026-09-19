# Operations Guide

Day-2 tasks for the three stacks (`fnx-dev-testenv-01`, `fnx-staging-staging-01`,
`fnx-prod-production`). Everything here is an Atmos command or an Atmos workflow; run
`atmos list workflows` for the full list. First-time deployment is covered in the
[Deployment Guide](./DEPLOYMENT_GUIDE.md).

1. [Routine checks](#routine-checks)
2. [Changing infrastructure](#changing-infrastructure)
3. [State locks](#state-locks)
4. [State recovery](#state-recovery)
5. [Disaster recovery](#disaster-recovery)
6. [Security and compliance](#security-and-compliance)
7. [Certificates](#certificates)
8. [Importing existing resources](#importing-existing-resources)
9. [Upgrading tool and provider versions](#upgrading-tool-and-provider-versions)
10. [Destroying a stack](#destroying-a-stack)

Workflows that take `-s <stack>` target that stack. Workflows whose usage shows `STACK=<stack>`
read the stack from that environment variable (or prompt for it).

---

## Routine checks

| Check | How | Automated |
|-------|-----|-----------|
| Drift | `atmos workflow drift-detection -f drift-detection -s <stack>` | Hourly, `drift-detection.yml` (read-only plan role; drift fails the job and the changes appear in the job summary) |
| Code security | `atmos workflow security-scan -f lint` (fails on HIGH/CRITICAL) or `atmos workflow security-scan-report -f lint` (report only). SARIF lands in `reports/` | Nightly `security-scan.yml`; every PR in `terraform-ci.yml` |
| Lint and validation | `atmos workflow lint -f lint`, `atmos workflow validate-all -f validate-enhanced` | Every PR |
| DR readiness | `STACK=<stack> atmos workflow dr-status -f disaster-recovery` | Manual `disaster-recovery.yml` |
| Security Hub findings | `atmos workflow security-audit -f security-hardening -s <stack>` | No |

Drift remediation, as the drift workflow prints it:

- Expected change made outside Terraform: codify it in the stack config, then `atmos terraform deploy <component> -s <stack>`.
- Unexpected change: re-apply the desired state with `atmos terraform deploy <component> -s <stack>`.
- Resource created outside Terraform: `atmos workflow import -f import -s <stack>`.

---

## Changing infrastructure

The normal path is a pull request. CI plans every affected component and comments the plans on the
PR. After the merge, CD deploys each affected stack in turn (dev, staging, prod), gated by that
stack's GitHub Environment. Give `fnx-prod-production` required reviewers.

Local equivalents:

```bash
atmos terraform plan <component> -s <stack>
atmos terraform deploy <component> -s <stack>
atmos workflow plan -f plan-environment -s <stack>       # every component, no apply
atmos workflow apply -f apply-environment -s <stack>     # every component, one confirmation
atmos workflow deploy-app -f deploy-application -s <stack>   # application layer on an existing foundation
atmos workflow hot-deploy -f deploy-application -s <stack>   # Lambda and API Gateway only
```

`terraform-cd.yml` can also be run by hand from the default branch to plan or deploy one stack,
optionally one component.

---

## State locks

The S3 backend uses Terraform's native lockfiles (`use_lockfile: true`): a lock is a
`<state key>.tflock` object next to the state in `fnx-terraform-state`. There is no DynamoDB
table.

```bash
STACK=<stack> atmos workflow list-locks -f state-operations   # lockfiles and their age
atmos workflow force-unlock -f state-operations -s <stack>    # release one component's lock
```

Only force-unlock when no plan or apply is running for that component, locally or in CI.

---

## State recovery

The state bucket is versioned. To see which state object belongs to an instance:

```bash
atmos describe component <component> -s <stack>   # .backend.workspace_key_prefix and .workspace
```

List recent versions (optionally narrowed to one root module's prefix):

```bash
STACK=<stack> COMPONENT_PREFIX=<root-module>/ atmos workflow recover-state -f disaster-recovery
```

The workflow prints the `aws s3api copy-object` command that makes an older version current
again. Run `atmos terraform plan <component> -s <stack>` afterwards to see what the restored state
implies before applying anything.

---

## Disaster recovery

Guided runbooks in `workflows/disaster-recovery.yaml`. They resolve tenant, region and state
bucket from the stack (`workflows/scripts/common/stack-context.sh`).

```bash
STACK=<stack> atmos workflow dr-status -f disaster-recovery          # readiness report
STACK=<stack> atmos workflow recover-database -f disaster-recovery   # RDS snapshots and PITR windows
STACK=<stack> atmos workflow dr-failover -f disaster-recovery        # failover to the DR region
STACK=<stack> atmos workflow dr-failback -f disaster-recovery        # back to the primary region
```

Failover and failback are interactive and are never run from CI. `disaster-recovery.yml` only
runs the read-only checks.

---

## Security and compliance

```bash
atmos workflow security-audit -f security-hardening -s <stack>   # Security Hub findings mapped to components
STACK=<stack> atmos workflow harden -f security-hardening        # GuardDuty, Security Hub, EBS default encryption, S3 account public-access block
STACK=<stack> atmos workflow harden-iam -f security-hardening    # account password policy
atmos workflow check -f compliance-check -s <stack>              # CIS, FSBP, PCI DSS, ... from Security Hub
atmos workflow report -f compliance-check -s <stack>             # writes compliance-report.md
```

`harden` and `harden-iam` ask before changing anything; declining runs them in report-only mode.
The compliance workflows need Security Hub enabled (`harden` does that).

In production, `guardduty/main` and `securityhub/main` are disabled stack instances, so these
services are managed by the `harden` workflow, not by Terraform.

---

## Certificates

ACM certificates are Terraform-managed (`acm/main`, `acm/services`) with DNS validation against
`settings.environment.hosted_zone_id`. For a certificate kept in Secrets Manager and synced into
Kubernetes:

```bash
atmos workflow rotate -f rotate-certificate   # prompts for secret name, namespace and optional ACM ARN
```

---

## Importing existing resources

```bash
atmos workflow import -f import -s <stack>
```

It prompts for the component instance, the Terraform resource address and the cloud resource ID,
imports after confirmation, and then shows the follow-up plan so the stack config can be
reconciled.

---

## Upgrading tool and provider versions

| What | Where |
|------|-------|
| Atmos minimum | `version.constraint.require` in `atmos.yaml`; the Atmos container tag in CI is `vars.ATMOS_VERSION` (default in each `.github/workflows/*.yml`) |
| Terraform | `terraform.dependencies.tools.terraform` in `stacks/orgs/fnx/_defaults.yaml`, plus the pins in `workflows/validate.yaml`, `workflows/validate-enhanced.yaml` and `workflows/lint.yaml` |
| Lint and scan tools | `dependencies.tools` in `workflows/lint.yaml` |
| AWS provider | `versions.tf` in each root module (`~> 6.65`) and shared module (`>= 6.0, < 7.0`) |

After a bump, run `atmos workflow validate-all -f validate-enhanced` and plan every stack
(`atmos workflow plan -f plan-environment -s <stack>`) before merging.

---

## Destroying a stack

```bash
atmos workflow destroy -f destroy-environment   # every component, reverse dependency order
atmos workflow destroy -f destroy-backend       # the state bucket and every state file in it
```

Both prompt for the stack name and require it typed again to confirm; do not pass `-s`. Destroying
the backend is irreversible and removes the state of every stack that shares the bucket.
