# Terraform Atmos Infrastructure

AWS infrastructure for the `fnx` tenant, defined as Terraform root modules and composed into
stacks with [Atmos](https://atmos.tools/). Deployments run through Atmos workflows locally and
Atmos Native CI in GitHub Actions.

> Before the first `apply`, replace the placeholder account IDs, organization ID, domains and
> alert recipients. The list is in
> [Manual prerequisites before first apply](./docs/DEPLOYMENT.md#manual-prerequisites-before-first-apply).

## Versions

| Tool | Version | Where it's pinned |
|------|---------|--------------------|
| Atmos | >= 1.229.0 | `atmos.yaml` (`version.constraint`, fatal) |
| Terraform | 1.16.3 | `stacks/orgs/fnx/_defaults.yaml` (`terraform.dependencies.tools`); Atmos installs it |
| AWS provider | `~> 6.65` in root modules, `>= 6.0, < 7.0` in shared modules | each `versions.tf` |
| Kubernetes / Helm providers | 3.x | `versions.tf` of the EKS-related components |

Lint, scan and AWS CLI tools (tflint, yamllint, trivy, checkov, aws-cli, jq) are pinned in the
workflows that use them and installed by the Atmos toolchain — no separate install step.

## Quick start

Prerequisites: Atmos >= 1.229.0 and AWS credentials for the target account. You do not need to
install Terraform — Atmos downloads the pinned version the first time a component runs.

```bash
atmos version                     # must be >= 1.229.0
atmos list stacks                 # fnx-dev-testenv-01, fnx-prod-production, fnx-staging-staging-01
atmos list components             # component instances and how many stacks use each
atmos list workflows              # every workflow with its file and description

# Offline checks (no AWS credentials needed)
atmos validate stacks
atmos workflow validate-all -f validate-enhanced

# First deployment of a stack (creates the state bucket, then IAM and VPCs)
atmos workflow full -f bootstrap -s fnx-dev-testenv-01

# Everything else, layer by layer (each layer is planned, confirmed, then applied)
atmos workflow deploy -f deploy-full-stack -s fnx-dev-testenv-01
```

The full procedure is in the [Deployment Guide](./docs/DEPLOYMENT.md).

## Layout

```
atmos.yaml                  Atmos CLI config (version constraint, paths, name_template, Native CI)
components/terraform/       Terraform root modules (+ _library/ shared modules)
modules/terraform/          Provider-less shared modules
stacks/
  orgs/fnx/                 Org, account and region defaults, and the three stacks
  catalog/                  Abstract component defaults, disabled variants, stack templates
  mixins/                   Tenant, stage and region mixins
workflows/                  Atmos workflows (+ scripts/ they call)
.github/workflows/          CI, CD, drift detection, security scan, DR checks
docs/                       Deployment and operations guides
```

## Stacks

Stack names come from `name_template` in `atmos.yaml`:
`{{ .settings.context.tenant }}-{{ .settings.context.stage }}-{{ .settings.context.environment }}`.

| Stack | Manifest | Region |
|-------|----------|--------|
| `fnx-dev-testenv-01` | `stacks/orgs/fnx/dev/eu-west-2/testenv-01.yaml` | eu-west-2 |
| `fnx-staging-staging-01` | `stacks/orgs/fnx/staging/eu-west-2/staging-01.yaml` | eu-west-2 |
| `fnx-prod-production` | `stacks/orgs/fnx/prod/eu-west-2/production.yaml` | eu-west-2 |

Each stack imports five domain files from its `components/` directory (`globals`, `networking`,
`security`, `compute`, `services`). See [stacks/README.md](./stacks/README.md).

## Components

`components/terraform/` holds 22 root modules, plus `_library/` (shared modules): `acm`, `apigateway`, `backend`, `backup`, `cost-optimization`, `dns`,
`ec2`, `ecs`, `eks`, `eks-addons`, `eks-backend-services`, `external-secrets`, `iam`,
`idp-platform`, `kms`, `lambda`, `monitoring`, `rds`, `secretsmanager`, `security-monitoring`,
`securitygroup`, `vpc`.

`idp-platform` is unsupported (no stack deploys it; `plan` fails unless
`acknowledge_unsupported = true`). Disabled instances (`metadata.enabled: false`): `iam/ci` (all
stacks), `iam/eks-node` (staging, prod), `iam/eks-cluster` (prod), `infrastructure/*`,
`vpc-flow-logs-bucket`, and in prod `guardduty/main`, `securityhub/main`, `network/vpc-peering`.

Every root module has `versions.tf`, `provider.tf` (AWS provider with `default_tags` from
`var.tags`) and a `README.md`. Tags come from `stacks/orgs/fnx/_defaults.yaml`: `Tenant`,
`Account`, `Environment`, `ManagedBy = "Terraform"`.

**State backend**: S3 bucket `fnx-terraform-state`, accessed through `fnx-terraform-backend-role`
in the management account. Locking uses Terraform's native S3 lockfiles (`use_lockfile: true`); no
DynamoDB lock table.

## Checks

```bash
atmos workflow tflint-init -f lint   # once: installs TFLint and the rulesets in .tflint.hcl
atmos workflow lint -f lint          # terraform fmt, yamllint, TFLint, Trivy
atmos workflow validate-all -f validate-enhanced   # schema, stacks, dependencies, yamllint, fmt, terraform validate
atmos workflow validate -f validate -s <stack>     # same, scoped to one stack
```

## CI/CD

GitHub Actions run Atmos Native CI inside the `ghcr.io/cloudposse/atmos` container and
authenticate to AWS with OIDC, not stored keys.

| Workflow | Trigger | What it does |
|----------|---------|--------------|
| `terraform-ci.yml` | PR, merge queue | Lint + validate-all, Trivy/Checkov security gate, plans affected components with the read-only role, comments on the PR |
| `terraform-cd.yml` | push to default branch, manual | Deploys each stack in turn (dev, staging, prod) since its `deployed/<stack>` tag, then moves the tag |
| `drift-detection.yml` | hourly, manual | Plans every stack read-only; drift fails the job |
| `security-scan.yml` | nightly | Report-only Trivy + Checkov scan |
| `disaster-recovery.yml` | manual, default branch | Read-only DR checks |

The AWS jobs above skip until the repository variable `AWS_PLAN_ROLE_ARN` is set — there is no AWS
account wired up yet. The PR security gate fails only on HIGH/CRITICAL findings not already in the
committed baselines (`.trivyignore.yaml`, `.checkov.baseline`).

## Documentation

- [Deployment Guide](./docs/DEPLOYMENT.md): prerequisites, bootstrap, layered deployment, rollback
- [Operations Guide](./docs/OPERATIONS.md): drift, locks, state recovery, DR, security checks
- [Stacks](./stacks/README.md)
- Component READMEs: `components/terraform/<component>/README.md`, `components/terraform/_library/README.md`

## License

MIT, see [LICENSE](./LICENSE).
