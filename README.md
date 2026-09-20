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
atmos list stacks                 # the three real stacks plus fnx-local-sandbox
atmos list components             # component instances and how many stacks use each
atmos list workflows              # every workflow with its file and description

# Offline checks (no AWS credentials needed)
atmos validate stacks
atmos workflow validate-all -f validate-enhanced

# Run it for real with no AWS account (Docker only) - see Sandbox below
atmos workflow sandbox -f sandbox

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
| `fnx-local-sandbox` | `stacks/orgs/fnx/local/eu-west-2/sandbox.yaml` | eu-west-2 (emulated) |

The three real stacks each import five domain files from their `components/` directory
(`globals`, `networking`, `security`, `compute`, `services`). See
[stacks/README.md](./stacks/README.md). `fnx-local-sandbox` is the local emulator stack — see
[Sandbox](#sandbox).

## Sandbox

The repository runs end to end with no AWS account, no credentials and no cost:

```bash
atmos workflow sandbox -f sandbox     # up, apply, destroy, down
```

That starts a [Floci](https://github.com/floci-dev/floci) container (MIT-licensed, a drop-in for
LocalStack CE, which was end-of-lifed in March 2026), applies `kms`, `vpc`, `dns`,
`secretsmanager` and `ecs` against it for real, then destroys them in reverse and stops the
container. Docker is the only prerequisite. Individual steps:

```bash
atmos emulator up aws -s fnx-local-sandbox
atmos terraform apply vpc/main -s fnx-local-sandbox --identity local-aws
atmos emulator down aws -s fnx-local-sandbox
```

This is the only gate that **executes** Terraform rather than analyzing it, and it has caught
bugs every static check missed — a NAT gateway created despite `enable_nat_gateway = false`, a
`coalesce()` that would have failed every `iam` plan, and a missing `database_subnet_ids` output
that would have broken all three `rds` instances at plan time.

Two things to know:

- The `local-aws` identity is deliberately **not** `default: true`, so no real environment can be
  pointed at the emulator by accident. Pass `--identity local-aws` explicitly.
- The emulator does not implement everything. `CreateDBSubnetGroup` is missing, so `rds` cannot be
  sandbox-tested at all; `CreateNetworkAcl` and `TagInstanceProfile` are missing, which is why the
  sandbox stack sets `manage_network_acls: false` and `create_vpc_iam_role: false`. Components
  with no sandbox instance are covered by validation and scanners only — their READMEs say so.

## Components

`components/terraform/` holds 27 root modules, plus `_library/` (shared modules): `acm`,
`apigateway`, `backend`, `backup`, `cognito`, `cost-optimization`, `dns`, `ec2`, `ecs`, `eks`,
`eks-addons`, `eks-backend-services`, `elasticache`, `external-secrets`, `guardduty`, `iam`,
`idp-platform`, `kms`, `lambda`, `monitoring`, `network`, `rds`, `secretsmanager`,
`security-monitoring`, `securitygroup`, `securityhub`, `vpc`.

`idp-platform` is unsupported (no stack deploys it; `plan` fails unless
`acknowledge_unsupported = true`). Every other component has at least one enabled instance —
there are no `metadata.enabled: false` instances left in `stacks/orgs/`.

An instance name does not have to match its component: `metadata.component` decides which module
runs. `network/main` and `network/services` are `dns` instances, while `network/vpc-peering` is
the `network` module. Read `metadata.component` before assuming.

Every root module has `versions.tf`, `provider.tf` (AWS provider with `default_tags` from
`var.tags`) and a `README.md`. Tags come from `stacks/orgs/fnx/_defaults.yaml`: `Tenant`,
`Account`, `Environment`, `ManagedBy = "Terraform"`.

**State backend**: S3 bucket `fnx-terraform-state`, accessed through `fnx-terraform-backend-role`
in the management account. Locking uses Terraform's native S3 lockfiles (`use_lockfile: true`); no
DynamoDB lock table.

## Adding a component

Components are scaffolded, not hand-written, so a new one satisfies the house rules (required
`tags` with a non-empty `Environment`, `enabled` gating, `versions.tf`, `provider.tf` with
`default_tags`, a README) before it is first linted:

```bash
atmos scaffold generate component . --force          # prompts for name, description, category
atmos scaffold generate catalog-entry . --force      # catalog defaults for an existing component
```

The target is the **repository root**, not the component directory: the template's `files[].target`
paths place each file, which is what lets one run emit both the component and its catalog entry.
Templates live in `scaffolds/` and are registered in `atmos.yaml` under `scaffold.templates`.
`--update` re-runs a template over existing files with a 3-way merge.

## Checks

```bash
atmos workflow tflint-init -f lint   # once: installs TFLint and the rulesets in .tflint.hcl
atmos workflow lint -f lint          # terraform fmt, yamllint, TFLint (instances + directories), Trivy
atmos workflow validate-all -f validate-enhanced   # schema, stacks, dependencies, yamllint, fmt, terraform validate
atmos workflow validate -f validate -s <stack>     # same, scoped to one stack
atmos workflow sandbox -f sandbox                  # the only gate that actually executes Terraform
```

Two gates are worth understanding, because both were added after they let real bugs through:

- **TFLint runs twice.** The instance pass resolves stack variables and catches what only appears
  with real inputs; the directory pass walks `components/terraform/*/` so a component with no
  stack instance cannot go unlinted. Ten of the components were unlinted before the second pass
  existed, while the gate reported "passed".
- **`check-dependencies.py` maps instances back to directories.** A deployable instance naming a
  component that does not exist used to pass every gate, because neither `atmos validate stacks`
  nor validate-all checks that the directory is there.

Note that `terraform validate` does **not** evaluate `variable` validation blocks, so validate-all
never exercises them. Changes to a validation block need a plan against real values to prove it
behaves — including a deliberately-bad case, to prove the check is reached at all.

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
