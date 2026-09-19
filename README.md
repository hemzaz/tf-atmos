# Terraform Atmos Infrastructure

AWS infrastructure for the `fnx` tenant, defined as Terraform root modules and composed into
stacks with [Atmos](https://atmos.tools/). Deployments run through Atmos workflows locally and
Atmos Native CI in GitHub Actions.

> Before the first `apply`, replace the placeholder account IDs, organization ID, domains and
> alert recipients. The list is in
> [Manual prerequisites before first apply](./docs/DEPLOYMENT_GUIDE.md#manual-prerequisites-before-first-apply).

## Versions

| Tool | Version | Where it is pinned |
|------|---------|--------------------|
| Atmos | >= 1.229.0 | `atmos.yaml` (`version.constraint`, fatal) |
| Terraform | 1.16.3 | `stacks/orgs/fnx/_defaults.yaml` (`terraform.dependencies.tools`); Atmos installs it |
| AWS provider | `~> 6.65` in root modules, `>= 6.0, < 7.0` in shared modules | each `versions.tf` |
| Kubernetes / Helm providers | 3.x | `versions.tf` of the EKS-related components |

Lint, scan and AWS CLI tools (tflint, yamllint, trivy, checkov, aws-cli, jq) are pinned in the
`dependencies.tools` of the workflows that use them and installed by the Atmos toolchain.

## Quick start

Prerequisites: Atmos >= 1.229.0 and AWS credentials for the target account. You do not need to
install Terraform: Atmos downloads the pinned version the first time a component runs.

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

The full procedure is in the [Deployment Guide](./docs/DEPLOYMENT_GUIDE.md).

## Stacks

Stack names come from `name_template` in `atmos.yaml`:
`{{ .settings.context.tenant }}-{{ .settings.context.stage }}-{{ .settings.context.environment }}`.

| Stack | Manifest | Region |
|-------|----------|--------|
| `fnx-dev-testenv-01` | `stacks/orgs/fnx/dev/eu-west-2/testenv-01.yaml` | eu-west-2 |
| `fnx-staging-staging-01` | `stacks/orgs/fnx/staging/eu-west-2/staging-01.yaml` | eu-west-2 |
| `fnx-prod-production` | `stacks/orgs/fnx/prod/eu-west-2/production.yaml` | eu-west-2 |

Each stack imports five domain files from its `components/` directory (`globals`, `networking`,
`security`, `compute`, `services`), which define several instances of the same root module
(`vpc/main`, `vpc/services`, `eks/main`, `eks/data`, ...). See [stacks/README.md](./stacks/README.md).

## Components

`components/terraform/` holds 22 root modules, plus `_library/` (reusable modules used by the
stack templates and some root modules) and `_catalog/` (module registry metadata):

`acm`, `apigateway`, `backend`, `backup`, `cost-optimization`, `dns`, `ec2`, `ecs`, `eks`,
`eks-addons`, `eks-backend-services`, `external-secrets`, `iam`, `idp-platform`, `kms`, `lambda`,
`monitoring`, `rds`, `secretsmanager`, `security-monitoring`, `securitygroup`, `vpc`.

Current state worth knowing:

- `kms` is a thin wrapper around the `_library/security/kms-multi-region` module. Production
  deploys it as `kms/main`, and EKS, EC2 and RDS in production read its key ARN.
- The `network/main` and `network/services` instances use the `dns` root module.
- `idp-platform` is unsupported: no stack deploys it, and `plan` fails unless
  `acknowledge_unsupported = true`. See its [README](./components/terraform/idp-platform/README.md).
- Disabled instances (`metadata.enabled: false`): `iam/ci` (all stacks), `iam/eks-node`
  (staging, prod), `iam/eks-cluster` (prod), `infrastructure/*`, `vpc-flow-logs-bucket`, and in
  prod `guardduty/main`, `securityhub/main` and `network/vpc-peering`.

Every root module has `versions.tf` (Terraform and provider constraints) and `provider.tf` (AWS
provider with `default_tags` from `var.tags`). The tags come from `stacks/orgs/fnx/_defaults.yaml`:
`Tenant`, `Account`, `Environment`, `ManagedBy = "Terraform"`.

## State backend

S3 bucket `fnx-terraform-state` in the stack's region, accessed through the
`fnx-terraform-backend-role` role in the management account. Locking uses Terraform's native S3
lockfiles (`use_lockfile: true`); there is no DynamoDB lock table. Atmos derives each instance's
state key from its root module (`workspace_key_prefix`) and the stack/instance workspace. The
`backend` component manages the bucket; `atmos workflow full -f bootstrap` creates it.

## Common commands

```bash
# One component instance
atmos terraform plan vpc/main -s fnx-dev-testenv-01
atmos terraform deploy vpc/main -s fnx-dev-testenv-01     # plan + apply
atmos terraform output vpc/main -s fnx-dev-testenv-01
atmos describe component vpc/main -s fnx-dev-testenv-01   # resolved vars, backend, dependencies

# A whole stack
atmos workflow plan -f plan-environment -s fnx-dev-testenv-01
atmos workflow apply -f apply-environment -s fnx-dev-testenv-01
atmos workflow deploy-networking -f deploy-full-stack -s fnx-dev-testenv-01   # one layer

# Checks
atmos workflow tflint-init -f lint   # once: installs TFLint and the rulesets in .tflint.hcl
atmos workflow lint -f lint
atmos workflow validate -f validate -s fnx-dev-testenv-01
atmos workflow drift-detection -f drift-detection -s fnx-dev-testenv-01

# State locks (native S3 lockfiles)
STACK=fnx-dev-testenv-01 atmos workflow list-locks -f state-operations
atmos workflow force-unlock -f state-operations -s fnx-dev-testenv-01

# Destroy one stack (you type the stack name to confirm; do not pass -s)
atmos workflow destroy -f destroy-environment
```

`atmos list workflows` shows the rest: stack templates, DR runbooks, compliance, security
hardening, certificate rotation and imports.

## CI/CD

GitHub Actions run Atmos Native CI inside the `ghcr.io/cloudposse/atmos` container and
authenticate to AWS with OIDC, not stored keys.

| Workflow | Trigger | What it does |
|----------|---------|--------------|
| `terraform-ci.yml` | pull request, merge queue | Runs the `lint` and `validate-all` workflows and a Trivy + Checkov security gate (SARIF to code scanning). `atmos describe affected` then feeds a matrix that plans each affected component with the read-only plan role and comments the plan summary on the PR |
| `terraform-cd.yml` | push to the default branch, manual dispatch | For each stack in turn (dev, staging, prod), deploys everything affected since that stack's `deployed/<stack>` tag, in dependency order, then moves the tag |
| `drift-detection.yml` | hourly, manual | Plans every stack with the read-only role; drift fails the job |
| `security-scan.yml` | nightly | Report-only Trivy + Checkov scan |
| `disaster-recovery.yml` | manual, default branch | Read-only DR checks |

The PR security gate fails only on HIGH/CRITICAL findings that are not in the committed baselines
(`.trivyignore.yaml`, `.checkov.baseline`). The nightly scan reports the full backlog.

GitHub setup is described in the workflow file headers and in the
[Deployment Guide](./docs/DEPLOYMENT_GUIDE.md#manual-prerequisites-before-first-apply): one GitHub
Environment per stack with `vars.AWS_ROLE_ARN`, the repository variable `AWS_PLAN_ROLE_ARN`, and
a `deployed/<stack>` tag per stack.

## Repository layout

```
atmos.yaml                  Atmos CLI config (version constraint, paths, name_template, Native CI)
components/terraform/       Terraform root modules (+ _library/, _catalog/)
modules/terraform/          Provider-less shared modules
stacks/
  orgs/fnx/                 Org, account and region defaults, and the three stacks
  catalog/                  Abstract component defaults, disabled variants, stack templates
  mixins/                   Tenant, stage and region mixins
workflows/                  Atmos workflows (+ scripts/ they call)
.github/workflows/          CI, CD, drift detection, security scan, DR checks
docs/                       Guides
```

## Documentation

- [Deployment Guide](./docs/DEPLOYMENT_GUIDE.md): prerequisites, bootstrap, layered deployment, rollback
- [Quick Deploy](./docs/QUICK_DEPLOY.md): the shortest path, and deploying a stack template
- [Operations Guide](./docs/OPERATIONS_GUIDE.md): drift, locks, state recovery, DR, security checks
- [Readiness status](./TURNKEY_READY.md): what is ready and what still needs human input
- [AI Integration Plan](./docs/AI_INTEGRATION_PLAN.md): proposed Atmos AI and MCP adoption
- [Stacks](./stacks/README.md) and [stack templates](./stacks/catalog/templates/README.md)
- Component READMEs: `components/terraform/<component>/README.md`

## License

MIT, see [LICENSE](./LICENSE).
